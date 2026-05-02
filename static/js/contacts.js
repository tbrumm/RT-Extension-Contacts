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

    // Re-run after HTMX swaps new content
    document.body.addEventListener('htmx:afterSwap', function () {
        colorizeAvatars();
        bindListItemClick();
    });

    document.addEventListener('DOMContentLoaded', function () {
        colorizeAvatars();
        bindListItemClick();
        bindFilterLinks();
    });
}());
