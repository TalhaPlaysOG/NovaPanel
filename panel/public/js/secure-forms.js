/**
 * Nova Panel - Secure form submission helper.
 *
 * When the panel is served over plain HTTP (IP access mode without TLS),
 * Chromium-based browsers show a full page interstitial before submitting any
 * form that carries sensitive fields ("The information you're about to submit
 * is not secure").
 *
 * Submitting the same payload with fetch() keeps CSRF tokens, validation
 * errors and flash messages intact while avoiding that native form navigation.
 * On HTTPS the script disables itself and forms behave natively.
 */
(function () {
    'use strict';

    if (window.location.protocol === 'https:') {
        return;
    }

    if (typeof window.fetch !== 'function' || typeof window.FormData !== 'function') {
        return;
    }

    var nativeSubmit = window.HTMLFormElement.prototype.submit;
    var pending = false;

    function isPostForm(form) {
        if (!form || form.tagName !== 'FORM' || form.hasAttribute('data-native-submit')) {
            return false;
        }

        if (form.hasAttribute('target') && form.getAttribute('target') !== '_self') {
            return false;
        }

        return (form.getAttribute('method') || 'get').toLowerCase() === 'post';
    }

    function submitterFor(form, event) {
        if (event && event.submitter) {
            return event.submitter;
        }

        var active = document.activeElement;
        if (active && active.form === form && active.type === 'submit') {
            return active;
        }

        return null;
    }

    function buildBody(form, submitter) {
        var body = new FormData(form);

        // Native submissions include the clicked submit button (used by Laravel
        // for method spoofing and by several admin actions).
        if (submitter && submitter.name) {
            body.append(submitter.name, submitter.value);
        }

        return body;
    }

    function render(html, url) {
        try {
            if (url && window.history && window.history.replaceState) {
                window.history.replaceState(null, '', url);
            }
        } catch (error) {
            // Cross-origin or sandboxed history updates are non-fatal.
        }

        // Replacing the document keeps behaviour close to a normal navigation:
        // scripts re-run, flash messages render and the URL is preserved.
        document.open();
        document.write(html);
        document.close();
    }

    function send(form, submitter) {
        if (pending) {
            return;
        }

        pending = true;

        var action = form.getAttribute('action') || window.location.href;

        fetch(action, {
            method: 'POST',
            body: buildBody(form, submitter),
            credentials: 'same-origin',
            redirect: 'follow',
            headers: {
                Accept: 'text/html,application/xhtml+xml'
            }
        })
            .then(function (response) {
                var contentType = response.headers.get('content-type') || '';

                if (contentType.indexOf('text/html') === -1) {
                    window.location.href = response.url || window.location.href;
                    return null;
                }

                return response.text().then(function (html) {
                    render(html, response.url);
                });
            })
            .catch(function () {
                pending = false;
                nativeSubmit.call(form);
            });
    }

    document.addEventListener(
        'submit',
        function (event) {
            var form = event.target;
            if (!isPostForm(form)) {
                return;
            }

            event.preventDefault();
            send(form, submitterFor(form, event));
        },
        true
    );

    window.HTMLFormElement.prototype.submit = function () {
        if (!isPostForm(this)) {
            return nativeSubmit.call(this);
        }

        send(this, null);
    };
})();
