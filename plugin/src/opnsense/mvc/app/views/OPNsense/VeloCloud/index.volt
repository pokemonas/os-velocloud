{#
 # Copyright (C) 2026 os-velocloud contributors
 # All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without modification,
 # are permitted provided that the following conditions are met:
 #
 # 1. Redistributions of source code must retain the above copyright notice,
 #    this list of conditions and the following disclaimer.
 #
 # 2. Redistributions in binary form must reproduce the above copyright notice,
 #    this list of conditions and the following disclaimer in the documentation
 #    and/or other materials provided with the distribution.
 #
 # THIS SOFTWARE IS PROVIDED “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES,
 # INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 # AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 # AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 # OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 # SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 # INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 # CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 # ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 # POSSIBILITY OF SUCH DAMAGE.
 #}

<script>
    $(document).ready(function () {
        const modeText = {
            'exact': "{{ lang._('loaded, built for this kernel') }}",
            'fallback': "{{ lang._('loaded, built for another kernel (fallback)') }}",
            'notloaded': "{{ lang._('not loaded') }}"
        };
        const nextText = {
            'exact': "{{ lang._('module for the installed kernel') }}",
            'fallback': "{{ lang._('fallback module (no module for the installed kernel yet)') }}",
            'none': "{{ lang._('no module') }}"
        };

        function cell(text, cls) {
            const $td = $('<td/>').text(text === undefined || text === null ? '' : text);
            if (cls) {
                $td.addClass(cls);
            }
            return $td;
        }

        function kv(label, value, cls) {
            return $('<tr/>').append($('<td style="width: 22%"/>').text(label), cell(value, cls));
        }

        function render(data) {
            const $drv = $('#vc_driver').empty();
            const $ports = $('#vc_ports tbody').empty();
            const $alert = $('#vc_alert').addClass('hidden').removeClass('alert-warning alert-danger');

            if (!data || data.status !== 'ok') {
                $alert.removeClass('hidden').addClass('alert-danger')
                    .text("{{ lang._('Could not read the status.') }}");
                return;
            }

            const d = data.driver;
            let health = d.mode === 'exact' ? 'text-success' : (d.loaded ? 'text-warning' : 'text-danger');
            let warning = '';
            if (!data.board) {
                warning = "{{ lang._('No Intel I354 found: this does not look like a VeloCloud Edge 520/540.') }}";
            } else if (data.reboot_pending) {
                warning = "{{ lang._('A new kernel is installed. Reboot to start it; the driver module for it is in place.') }}";
            } else if (!d.loaded) {
                warning = "{{ lang._('The I354 driver is not loaded: LAN1-8, GE1 and GE2 are not available. It is loaded by the loader, so a reboot is needed after installing or enabling it.') }}";
            } else if (d.mode === 'fallback') {
                warning = data.available_for_kernel ?
                    "{{ lang._('A module built for the running kernel is installed now. Reboot to switch to it.') }}" :
                    "{{ lang._('No module was built for the running kernel yet; a module for another kernel is used. Check System: Firmware for an os-velocloud update.') }}";
            }
            if (warning !== '') {
                $alert.removeClass('hidden').addClass(d.loaded ? 'alert-warning' : 'alert-danger').text(warning);
            }

            $drv.append(kv("{{ lang._('Running kernel') }}", data.kernel.uname));
            $drv.append(kv("{{ lang._('Driver') }}", modeText[d.mode] + (d.built_for ? ' (' + d.built_for + ')' : ''), health));
            $drv.append(kv("{{ lang._('Next boot') }}", (nextText[d.next_boot] || d.next_boot) +
                (d.next_module ? ' (' + d.next_module + ')' : '')));
            $drv.append(kv("{{ lang._('Modules in package') }}", data.available.map(function (m) {
                return (m.ref ? m.ref + ' ' : '') + '(' + m.commit + ')' +
                    (m.commit === data.kernel.commit ? ' ✓' : '');
            }).join(', ') || "{{ lang._('none') }}"));

            data.ports.forEach(function (p) {
                $ports.append($('<tr/>').append(
                    cell(p.jack),
                    cell(p.up ? "{{ lang._('up') }}" : "{{ lang._('down') }}", p.up ? 'text-success' : 'text-muted'),
                    cell(p.up && p.speed ? p.speed + ' Mbit/s ' + p.duplex : ''),
                    cell(p.interface),
                    cell(p.assigned),
                    cell(p.chip + (p.note ? ' (' + p.note + ')' : ''))
                ));
            });
        }

        function refresh() {
            ajaxGet('/api/velocloud/status/get', {}, function (data) {
                render(data);
            });
        }

        refresh();
        setInterval(function () {
            if ($('#tab_ports').hasClass('active')) {
                refresh();
            }
        }, 5000);

        mapDataToFormUI({'frm_general': '/api/velocloud/settings/get'}).done(function () {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        $('#reconfigureAct').SimpleActionButton({
            onPreAction: function () {
                const dfObj = new $.Deferred();
                saveFormToEndpoint('/api/velocloud/settings/set', 'frm_general',
                    function () { dfObj.resolve(); }, true, function () { dfObj.reject(); });
                return dfObj;
            }
        });

        $('a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
            $('#reconfigure_section').toggleClass('hidden', $(e.target).attr('href') !== '#settings');
        });
        $('#reconfigure_section').addClass('hidden');
    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active" id="tab_ports"><a data-toggle="tab" href="#ports">{{ lang._('Ports') }}</a></li>
    <li><a data-toggle="tab" href="#settings">{{ lang._('Settings') }}</a></li>
</ul>

<div class="tab-content content-box">
    <div id="ports" class="tab-pane fade in active">
        <div class="alert hidden" role="alert" id="vc_alert" style="margin: 10px;"></div>
        <table class="table table-striped table-condensed">
            <tbody id="vc_driver"></tbody>
        </table>
        <table class="table table-striped table-condensed" id="vc_ports">
            <thead>
                <tr>
                    <th>{{ lang._('Port') }}</th>
                    <th>{{ lang._('Link') }}</th>
                    <th>{{ lang._('Speed') }}</th>
                    <th>{{ lang._('Interface') }}</th>
                    <th>{{ lang._('Assigned') }}</th>
                    <th>{{ lang._('Chip') }}</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
        <div style="padding: 10px;" class="text-muted">
            {{ lang._('LAN1-4 and LAN5-8 are two unmanaged switches: each group shares one interface (vcigb1 and vcigb0).') }}
        </div>
    </div>
    <div id="settings" class="tab-pane fade">
        {{ partial("layout_partials/base_form", ['fields': generalForm, 'id': 'frm_general']) }}
    </div>
</div>

<div id="reconfigure_section">
{{ partial('layout_partials/base_apply_button', {'data_endpoint': '/api/velocloud/service/reconfigure'}) }}
</div>
