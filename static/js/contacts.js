(function () {
    'use strict';
    var $ = jQuery;

    // Colour contact avatars by first letter
    function colorizeAvatars() {
        document.querySelectorAll('.contact-avatar .rounded-circle').forEach(function (el) {
            var letter = (el.textContent.trim()[0] || 'A').toUpperCase();
            el.classList.add('contact-avatar-' + letter);
        });
    }

    // Mark the active list item
    function bindListItemClick() {
        document.querySelectorAll('.contacts-list-item').forEach(function (el) {
            el.addEventListener('htmx:afterRequest', function () {
                document.querySelectorAll('.contacts-list-item').forEach(function (i) {
                    i.classList.remove('active');
                });
                el.classList.add('active');
            });
        });
    }

    // Mark active filter button
    function bindFilterLinks() {
        document.querySelectorAll('.contacts-filter-link').forEach(function (el) {
            el.addEventListener('click', function () {
                document.querySelectorAll('.contacts-filter-link').forEach(function (l) {
                    l.classList.remove('active');
                });
                el.classList.add('active');
            });
        });
    }

    // Avatar fallback: RT image → Gravatar → initials div
    window.contactAvatarFallback = function (img) {
        if (img.dataset.step === 'rt') {
            img.dataset.step = 'gravatar';
            img.src = img.dataset.gravatar;
        } else {
            var size   = parseInt(img.dataset.size || '40');
            var margin = img.dataset.margin || '0';
            var fs     = Math.round(size * 0.37);
            var div    = document.createElement('div');
            div.setAttribute('style',
                'width:' + size + 'px;height:' + size + 'px;border-radius:50%;flex-shrink:0;' +
                'margin-right:' + margin + ';' +
                'background:' + (img.dataset.color || '#6c757d') + ';' +
                'display:flex;align-items:center;justify-content:center;' +
                'color:#fff;font-weight:700;font-size:' + fs + 'px;letter-spacing:.02em;');
            div.textContent = img.dataset.initials || '?';
            img.parentNode.replaceChild(div, img);
        }
    };

    // Re-run after HTMX swaps new content
    // Use document instead of document.body — body is null when <head> scripts run
    document.addEventListener('htmx:afterSwap', function () {
        colorizeAvatars();
        bindListItemClick();
    });

    document.addEventListener('DOMContentLoaded', function () {
        colorizeAvatars();
        bindListItemClick();
        bindFilterLinks();
    });
}());
