<?php
/**
 * The base configuration for WordPress
 *
 * The wp-config.php creation script uses this file during the
 * installation. You don't have to use the web site, you can
 * copy this file to "wp-config.php" and fill in the values.
 *
 * This file contains the following configurations:
 *
 * * MySQL settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * @link https://codex.wordpress.org/Editing_wp-config.php
 *
 * @package WordPress
 */

// ** MySQL settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define('DB_NAME', 'wordpress');

/** MySQL database username */
define('DB_USER', 'wpuser');

/** MySQL database password */
define('DB_PASSWORD', 'wppasswd');

/** MySQL hostname */
define('DB_HOST', 'db');

/** Database Charset to use in creating database tables. */
define('DB_CHARSET', 'utf8');

/** The Database Collate type. Don't change this if in doubt. */
define('DB_COLLATE', '');

/**#@+
 * Authentication Unique Keys and Salts.
 *
 * Change these to different unique phrases!
 * You can generate these using the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}
 * You can change these at any point in time to invalidate all existing cookies. This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define('AUTH_KEY',         'ONLY_AVAILABLE_IN_DOCKER');
define('SECURE_AUTH_KEY',  'ONLY_AVAILABLE_IN_DOCKER');
define('LOGGED_IN_KEY',    'ONLY_AVAILABLE_IN_DOCKER');
define('NONCE_KEY',        'ONLY_AVAILABLE_IN_DOCKER');
define('AUTH_SALT',        'ONLY_AVAILABLE_IN_DOCKER');
define('SECURE_AUTH_SALT', 'ONLY_AVAILABLE_IN_DOCKER');
define('LOGGED_IN_SALT',   'ONLY_AVAILABLE_IN_DOCKER');
define('NONCE_SALT',       'ONLY_AVAILABLE_IN_DOCKER');

/**#@-*/

/**
 * WordPress Database Table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix  = "wp_app";

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the Codex.
 *
 * @link https://codex.wordpress.org/Debugging_in_WordPress
 */
define('WP_DEBUG', false);

// If we're behind a proxy server and using HTTPS, we need to alert Wordpress of that fact
// see also http://codex.wordpress.org/Administration_Over_SSL#Using_a_Reverse_Proxy
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
	$_SERVER['HTTPS'] = 'on';
}

/* That's all, stop editing! Happy blogging. */
/** Absolute path to the WordPress directory. */
if ( !defined('ABSPATH') )
	define('ABSPATH', dirname(__FILE__) . '/');


/* export every environment var in the form  WORDPRESS__<k> = v
 * as WP_k = v wordpress setting */
function define_env_settings($key, $value) {
    if (ereg("^WORDPRESS__", $key)) {
        $val = $value;
        define(preg_replace("WORDPRESS__", "WP_", $key), $val);
        var_dump(preg_replace("WORDPRESS__", "WP_", $key));
        var_dump($val);
    }
}
array_walk($_ENV, define_env_settings);

/** Sets up WordPress vars and included files. */
if (file_exists(ABSPATH . 'local.php')) {
  require_once(ABSPATH . 'local.php');
}
require_once(ABSPATH . 'wp-settings.php');
// Use X-Forwarded-For HTTP Header to Get Visitor's Real IP Address
if ( isset( $_SERVER['HTTP_X_FORWARDED_FOR'] ) ) {
    $http_x_headers = explode( ',', $_SERVER['HTTP_X_FORWARDED_FOR'] );
    $_SERVER['REMOTE_ADDR'] = $http_x_headers[0];
}
