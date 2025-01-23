/*
 * Export global variables used in deprecated sprockets-based
 * javascript assets.
 */
import i18n from '../i18n/i18n';
import Dropzone from 'dropzone';
import jQuery from 'jquery';
import ready from '../util/ready';

// sweetalert2: Export the XUI mixin as the default for both, plain and
// xuiSwal usage. All legacy code should use the same default config.
import swal from '../util/swal';
import { showLoading, hideLoading } from '../util/loading';
import sanitize from '../util/sanitize';

/**
 * Legacy utility to add translations
 * Use explicit import instead
 * @deprecated
 */
window.I18n = i18n;

/**
 * jQuery for legacy inline JS.
 * Do not use in webpack JS code.
 * @deprecated
 */
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const $ = jQuery;

window.Swal = swal;
window.xuiSwal = swal;

/**
 * Legacy utility to show and hide loading dimmer
 * Use explicit import instead
 * @deprecated
 */
window.showLoading = showLoading;
window.hideLoading = hideLoading;

/**
 * Legacy utility to sanitize input
 * Use explicit import instead
 * @deprecated
 */
window.sanitize = sanitize;

/**
 * Only use for invoking the function from legacy inline JS.
 * Use the default export instead.
 * @deprecated
 */
window.ready = ready;

/**
 * Dropzone is a global object used in legacy inline JS.
 * Do not use in webpack JS code.
 * @deprecated
 */
window.Dropzone = Dropzone;
