#!/bin/sh
# FreshRSS multi-category entrypoint wrapper
# If FRESHRSS_API_PASSWORD is set, auto-configures the Fever API key for the default user.
# The default user is read from FreshRSS's own data/config.php — no extra env vars needed.

setup_fever() {
    # Read default_user from FreshRSS system config
    local user
    user=$(php -r "
\$c = include '/var/www/FreshRSS/data/config.php';
echo \$c['default_user'] ?? '';
" 2>/dev/null)

    if [ -z "$user" ]; then
        echo "⚠️  Fever setup: could not determine default_user from config.php" >&2
        return 1
    fi

    # Set API password
    php /var/www/FreshRSS/cli/update-user.php \
        --user "$user" --api-password "$FRESHRSS_API_PASSWORD" >/dev/null 2>&1

    # Create Fever key file
    php -r "
define('FRESHRSS_PATH', '/var/www/FreshRSS');
define('DATA_PATH', '/var/www/FreshRSS/data');
require '/var/www/FreshRSS/constants.php';
require LIB_PATH.'/lib_rss.php';
FreshRSS_Context::initSystem();
FreshRSS_Context::initUser('$user');
\$salt = FreshRSS_Context::systemConf()->salt;
\$feverKey = FreshRSS_Context::userConf()->feverKey;
if (empty(\$feverKey)) { exit(1); }
\$dir = DATA_PATH.'/fever';
@mkdir(\$dir, 0755, true);
chown(\$dir, 'www-data');
\$keyFile = \$dir.'/.key-'.sha1(\$salt).'-'.\$feverKey.'.txt';
file_put_contents(\$keyFile, '$user');
chown(\$keyFile, 'www-data');
echo '✅ Fever key configured for $user' . PHP_EOL;
" 2>/dev/null
}

if [ -n "$FRESHRSS_API_PASSWORD" ]; then
    # Wait for user config in background, then set up Fever
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

# Hand off to original entrypoint
exec /var/www/FreshRSS/Docker/entrypoint.sh "$@"
