#!/usr/local/bin/python3

"""
os-velocloud: port and driver status of a VeloCloud Edge 520/540 as JSON.

Sources: uname -v (running kernel), /var/run/velocloud.state (select.sh:
installed kernel and the modules put in place for the loader), hw.vcigb.* and
dev.vcigb.N.vc_* sysctls (if_vcigb), ifconfig.
"""

import glob
import json
import os
import re
import subprocess

MODDIR = '/usr/local/lib/velocloud'
STATE = '/var/run/velocloud.state'

# switch port 0..3 -> front jack, measured by walking a cable round the jacks
SWITCH_JACKS = {
    0: ['LAN6', 'LAN7', 'LAN5', 'LAN8'],    # I354 func 0, switch A
    1: ['LAN2', 'LAN1', 'LAN4', 'LAN3'],    # I354 func 1, switch B
}
JACK_ORDER = ['LAN%d' % i for i in range(1, 9)] + ['GE1', 'GE2', 'SFP1', 'SFP2']


def run(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ''


def sysctl(name):
    out = run('/sbin/sysctl', '-n', name)
    return out.rstrip('\n') if out != '' else None


def read_kv(path):
    result = {}
    try:
        with open(path) as f:
            for line in f:
                if '=' in line:
                    k, v = line.rstrip('\n').split('=', 1)
                    result[k] = v
    except OSError:
        pass
    return result


def ifconfig(ifname):
    out = run('/sbin/ifconfig', ifname)
    info = {'exists': out != '', 'description': '', 'status': '', 'media': ''}
    for line in out.splitlines():
        line = line.strip()
        if line.startswith('description:'):
            info['description'] = line.split(':', 1)[1].strip()
        elif line.startswith('status:'):
            info['status'] = line.split(':', 1)[1].strip()
        elif line.startswith('media:'):
            info['media'] = line.split(':', 1)[1].strip()
    m = re.search(r'\((\d+)base[^ ]*\s*<([a-z-]+)', info['media'])
    info['speed'] = m.group(1) if m else ''
    info['duplex'] = ('full' if 'full' in m.group(2) else 'half') if m else ''
    info['up'] = info['status'] == 'active'
    return info


def ports():
    rows = []
    unit = 0
    while sysctl('dev.vcigb.%d.%%desc' % unit) is not None:
        ifname = 'vcigb%d' % unit
        role = sysctl('dev.vcigb.%d.vc_role' % unit) or 'none'
        func = sysctl('dev.vcigb.%d.vc_func' % unit)
        func = int(func) if func is not None and func.isdigit() else -1
        ifc = ifconfig(ifname)
        if role == 'switch' and func in SWITCH_JACKS:
            lines = (sysctl('dev.vcigb.%d.vc_ports' % unit) or '').splitlines()
            for line in lines:
                parts = line.split()
                if not parts or not parts[0].isdigit() or int(parts[0]) > 3:
                    continue
                port = int(parts[0])
                ok = len(parts) == 4
                rows.append({
                    'jack': SWITCH_JACKS[func][port],
                    'interface': ifname,
                    'assigned': ifc['description'],
                    'chip': '88E6176 %s port %d' % ('A' if func == 0 else 'B', port),
                    'up': ok and parts[1] == 'up',
                    'speed': parts[2] if ok and parts[1] == 'up' else '',
                    'duplex': parts[3] if ok and parts[1] == 'up' else '',
                    'note': '' if ok else 'read error',
                })
        elif role == 'extphy':
            rows.append({
                'jack': 'GE%d' % (func - 1),
                'interface': ifname,
                'assigned': ifc['description'],
                'chip': '88E1514 PHY %d' % (func - 2),
                'up': ifc['up'],
                'speed': ifc['speed'] if ifc['up'] else '',
                'duplex': ifc['duplex'] if ifc['up'] else '',
                'note': '',
            })
        unit += 1

    # SFP cages: the I350 (igb) ports, in unit order
    sfp = 1
    for unit in range(0, 8):
        desc = sysctl('dev.igb.%d.%%desc' % unit)
        if desc is None:
            continue
        ifname = 'igb%d' % unit
        ifc = ifconfig(ifname)
        rows.append({
            'jack': 'SFP%d' % sfp,
            'interface': ifname,
            'assigned': ifc['description'],
            'chip': 'I350',
            'up': ifc['up'],
            'speed': ifc['speed'] if ifc['up'] else '',
            'duplex': ifc['duplex'] if ifc['up'] else '',
            'note': '',
        })
        sfp += 1
        if sfp > 2:
            break

    rows.sort(key=lambda r: JACK_ORDER.index(r['jack']) if r['jack'] in JACK_ORDER else 99)
    return rows


def modules():
    result = []
    for info in sorted(glob.glob(os.path.join(MODDIR, '*', 'info'))):
        kv = read_kv(info)
        kv['commit'] = kv.get('commit', os.path.basename(os.path.dirname(info)))
        result.append(kv)
    return result


def main():
    uname = run('/usr/bin/uname', '-v').strip()
    m = re.search(r'-([0-9a-f]{12}) ', uname + ' ')
    kcommit = m.group(1) if m else ''
    loaded = subprocess.run(['/sbin/kldstat', '-q', '-m', 'vcigb']).returncode == 0
    built_for = (sysctl('hw.vcigb.kerncommit') or '') if loaded else ''
    state = read_kv(STATE)
    avail = modules()
    installed_kernel = state.get('kernel', '')

    if not loaded:
        mode = 'notloaded'
    elif built_for == kcommit:
        mode = 'exact'
    else:
        mode = 'fallback'

    result = {
        'kernel': {'uname': uname, 'commit': kcommit, 'installed': installed_kernel},
        'board': run('/usr/sbin/pciconf', '-l').find('chip=0x1f418086') >= 0,
        'driver': {
            'loaded': loaded,
            'built_for': built_for,
            'matches': mode == 'exact',
            'mode': mode,
            'next_boot': 'exact' if state.get('exact') else ('fallback' if state.get('fallback') else 'none'),
            'next_module': state.get('exact') or state.get('fallback', ''),
        },
        # a kernel update was installed but the box has not rebooted yet
        'reboot_pending': bool(installed_kernel and kcommit and installed_kernel != kcommit),
        'available': avail,
        'available_for_kernel': any(a['commit'] == kcommit for a in avail),
        'ports': ports(),
    }
    print(json.dumps(result))


if __name__ == '__main__':
    main()
