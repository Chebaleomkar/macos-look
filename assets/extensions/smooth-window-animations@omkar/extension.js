import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

/**
 * Smooth Window Animations
 *
 * GNOME Shell animates window resizes with a hard-coded 250 ms
 * EASE_OUT_QUAD transition (js/ui/windowManager.js). That curve starts at
 * full speed, which makes maximize/restore feel almost instantaneous.
 *
 * The Shell connects its own size-change handlers at startup, so replacing
 * WindowManager methods afterwards has no effect. Instead we listen to the
 * same signals: when a maximize/unmaximize is being prepared, we temporarily
 * override `ease()` on the window actor and on the snapshot clone that the
 * Shell creates for the transition. Both transitions then run longer and
 * with a gentle ease-in-out curve. Everything is restored immediately when
 * the resize has been applied.
 */

const DURATION = 400; // ms (Shell default: 250)
const MODE = Clutter.AnimationMode.EASE_IN_OUT_QUAD;
const DEBUG = false;

function debug(message) {
    if (DEBUG)
        console.log(`[smooth-wm] ${message}`);
}

function isTargetChange(whichChange) {
    return whichChange === Meta.SizeChange.MAXIMIZE ||
        whichChange === Meta.SizeChange.UNMAXIMIZE;
}

export default class SmoothWindowAnimationsExtension extends Extension {
    enable() {
        this._patches = [];
        this._sizeChangeId = 0;
        this._sizeChangedId = 0;

        const shellwm = Main.wm?._shellwm;
        if (!shellwm) {
            console.warn('[smooth-wm] ShellWM unavailable; extension inactive');
            return;
        }

        this._sizeChangeId = shellwm.connect('size-change',
            (_wm, actor, whichChange) => {
                if (!isTargetChange(whichChange))
                    return;

                const clone = actor.__animationInfo?.clone;
                if (!clone)
                    return; // The Shell chose not to animate this change.

                debug(`size-change ${whichChange}: patching actor + clone`);
                this._patch(actor);
                this._patch(clone);
            });

        this._sizeChangedId = shellwm.connect('size-changed', (_wm, actor) => {
            this._unpatch(actor);
            const clone = actor.__animationInfo?.clone;
            if (clone)
                this._unpatch(clone);
        });
    }

    disable() {
        if (this._sizeChangeId && Main.wm?._shellwm) {
            Main.wm._shellwm.disconnect(this._sizeChangeId);
            Main.wm._shellwm.disconnect(this._sizeChangedId);
        }
        this._sizeChangeId = 0;
        this._sizeChangedId = 0;

        for (const [actor] of this._patches)
            this._restore(actor);
        this._patches = [];
    }

    _patch(actor) {
        if (this._patches.some(([a]) => a === actor))
            return;

        const original = actor.ease;
        if (typeof original !== 'function')
            return;

        const patched = function (props) {
            if (props &&
                typeof props.duration === 'number' &&
                props.mode === Clutter.AnimationMode.EASE_OUT_QUAD) {
                debug(`ease ${props.duration}ms -> ${DURATION}ms`);
                props = {...props, duration: DURATION, mode: MODE};
            }
            return original.call(this, props);
        };
        patched.__smoothWindowAnimations = true;

        actor.ease = patched;
        this._patches.push([actor, patched]);
    }

    _unpatch(actor) {
        const index = this._patches.findIndex(([a]) => a === actor);
        if (index === -1)
            return;

        this._restore(actor);
        this._patches.splice(index, 1);
    }

    _restore(actor) {
        try {
            if (actor.ease?.__smoothWindowAnimations)
                delete actor.ease;
        } catch (e) {
            // Actor may already be destroyed; nothing to restore.
        }
    }
}
