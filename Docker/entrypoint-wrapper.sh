#!/bin/sh
# FreshRSS multi-category entrypoint wrapper
# If FRESHRSS_API_PASSWORD is set, auto-enables API and configures Fever key for the default user.

setup_fever() {
    local user
    user=$(php -r "\$c=@include '/var/www/FreshRSS/data/config.php'; echo \$c['default_user']??'';" 2>/dev/null)

    if [ -z "$user" ]; then
        echo "⚠️  Fever setup: could not determine default_user" >&2
        return 1
    fi

    # Fix ownership so www-data can write configs
    chown -R www-data:www-data "/var/www/FreshRSS/data/users/${user}" 2>/dev/null
    chown www-data:www-data /var/www/FreshRSS/data/config.php 2>/dev/null

    # Set API password for user
    php /var/www/FreshRSS/cli/update-user.php \
        --user "$user" --api-password "$FRESHRSS_API_PASSWORD" >/dev/null 2>&1

    # Enable API globally + per-user, create Fever key file
    php -r "
define('FRESHRSS_PATH', '/var/www/FreshRSS');
define('DATA_PATH', '/var/www/FreshRSS/data');
require '/var/www/FreshRSS/constants.php';
require LIB_PATH.'/lib_rss.php';
FreshRSS_Context::initSystem();

// Enable API globally
\$sysConf = FreshRSS_Context::systemConf();
\$sysConf->api_enabled = true;
\$sysConf->save();

// Enable API for user
FreshRSS_Context::initUser('$user');
\$conf = FreshRSS_Context::userConf();
\$conf->api_enabled = true;
\$conf->save();

// Re-init to pick up feverKey set by update-user.php
FreshRSS_Context::initSystem();
FreshRSS_Context::initUser('$user');
\$salt = FreshRSS_Context::systemConf()->salt;
\$feverKey = FreshRSS_Context::userConf()->feverKey;
if (empty(\$feverKey)) { echo '⚠️  No feverKey found' . PHP_EOL; exit(1); }

\$dir = DATA_PATH.'/fever';
@mkdir(\$dir, 0755, true);
chown(\$dir, 'www-data');
\$keyFile = \$dir.'/.key-'.sha1(\$salt).'-'.\$feverKey.'.txt';
file_put_contents(\$keyFile, '$user');
chown(\$keyFile, 'www-data');
echo '✅ Fever API enabled + key configured for $user' . PHP_EOL;
" 2>/dev/null
}

if [ -n "$FRESHRSS_API_PASSWORD" ]; then
    (
        TRIES=0
        while [ $TRIES -lt 60 ]; do
            CONFIG=$(php -r "\$c=@include '/var/www/FreshRSS/data/config.php'; echo \$c['default_user']??'';" 2>/dev/null)
            if [ -n "$CONFIG" ] && [ -f "/var/www/FreshRSS/data/users/${CONFIG}/config.php" ]; then
                setup_fever
                exit 0
            fi
            sleep 1
            TRIES=$((TRIES + 1))
        done
        echo "⚠️  Fever setup timed out" >&2
    ) &
fi

exec /var/www/FreshRSS/Docker/entrypoint.sh "$@"
