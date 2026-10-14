/*
 * Copyright (C) 2026 os-velocloud contributors
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

export default class VeloCloud extends BaseWidget {
    constructor() {
        super();
        this.tickTimeout = 5;
    }

    getMarkup() {
        return $(`
            <div id="vc-widget" style="margin: 8px;">
                <div id="vc-widget-msg" class="text-warning" style="margin-bottom: 6px;"></div>
                <div id="vc-widget-ports" style="display: flex; flex-wrap: wrap; gap: 6px;"></div>
            </div>
        `);
    }

    async onWidgetTick() {
        const data = await this.ajaxCall('/api/velocloud/status/get');
        const $ports = $('#vc-widget-ports').empty();
        const $msg = $('#vc-widget-msg').text('');

        if (!data || data.status !== 'ok') {
            $msg.text(this.translations.nodata);
            return;
        }
        if (!data.driver.loaded) {
            $msg.text(this.translations.notloaded);
        } else if (!data.driver.matches) {
            $msg.text(this.translations.mismatch);
        }

        data.ports.forEach((p) => {
            const $tile = $('<div/>').css({
                width: '62px', padding: '4px 2px', 'text-align': 'center', 'border-radius': '4px',
                border: '1px solid', 'font-size': '11px', 'line-height': '1.3'
            }).addClass(p.up ? 'text-success' : 'text-muted');
            $tile.attr('title', `${p.interface} ${p.assigned} ${p.chip}`);
            $tile.append($('<b/>').text(p.jack), $('<br/>'),
                $('<span/>').text(p.up ? (p.speed ? `${p.speed}M` : this.translations.up) : this.translations.down));
            $ports.append($tile);
        });
    }
}
