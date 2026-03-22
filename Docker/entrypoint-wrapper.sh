#!/bin/sh
# FreshRSS multi-category entrypoint wrapper
# Auto-configures Fever API key on first start if FRESHRSS_API_PASSWORD is set.

# Call the original entrypoint first (it handles install, user creation, cron, apache)
/var/www/FreshRSS/Docker/entrypoint.sh "$@" &
ORIG_PID=$!

# Wait for FreshRSS data to be initialized (up to 30s)
if [ -n "$FRESHRSS_API_PASSWORD" ] && [ -n "$FRESHRSS_DEFAULT_USER" ]; then
    TRIES=0
    while [ $TRIES -lt 30 ]; do
        if [ -f "/var/www/FreshRSS/data/users/${FRESHRSS_DEFAULT_USER}/config.php" ]; then
            break
        fi
        sleep 1
        TRIES=$((TRIES + 1))
    done

    if [ -f "/var/www/FreshRSS/data/users/${FRESHRSS_DEFAULT_USER}/config.php" ]; then
        # Set API password (idempotent)
        php /var/www/FreshRSS/cli/update-user.php \
            --user "$FRESHRSS_DEFAULT_USER" \
            --api-password "$FRESHRSS_API_PASSWORD" \
            >/dev/null 2>&1

        # Create Fever key file
        php -r "
define('FRESHRSS_PATH', '/var/www/FreshRSS');
define('DATA_PATH', '/var/www/FreshRSS/data');
require '/var/www/FreshRSS/constants.php';
require LIB_PATH.'/lib_rss.php';
FreshRSS_Context::initSystem();
FreshRSS_Context::initUser('${FRESHRSS_DEFAULT_USER}');
\$salt = FreshRSS_Context::systemConf()->salt;
\$feverKey = FreshRSS_Context::userConf()->feverKey;
if (empty(\$feverKey)) { exit(1); }
\$keyHash = sha1(\$salt);
\$dir = DATA_PATH.'/fever';
@mkdir(\$dir, 0755, true);
chown(\$dir, 'www-data');
\$keyFile = \$dir.'/.key-'.\$keyHash.'-'.\$feverKey.'.txt';
file_put_contents(\$keyFile, '${FRESHRSS_DEFAULT_USER}');
chown(\$keyFile, 'www-data');
echo '✅ Fever key configured for ${FRESHRSS_DEFAULT_USER}' . PHP_EOL;
" 2>/dev/null
    else
        echo "⚠️  Fever setup skipped: user config not found after 30s"
    fi
fi

wait $ORIG_PID
