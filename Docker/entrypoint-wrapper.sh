#!/bin/sh
# FreshRSS multi-category entrypoint wrapper
# Auto-configures Fever API key, then hands off to the original entrypoint.

setup_fever() {
    local user="$1"
    local pass="$2"

    # Set API password
    php /var/www/FreshRSS/cli/update-user.php \
        --user "$user" --api-password "$pass" >/dev/null 2>&1

    # Create Fever key file
    php -r "
define('FRESHRSS_PATH', '/var/www/FreshRSS');
define('DATA_PATH', '/var/www/FreshRSS/data');
require '/var/www/FreshRSS/constants.php';
require LIB_PATH.'/lib_rss.php';
FreshRSS_Context::initSystem();
FreshRSS_Context::initUser('${user}');
\$salt = FreshRSS_Context::systemConf()->salt;
\$feverKey = FreshRSS_Context::userConf()->feverKey;
if (empty(\$feverKey)) { exit(1); }
\$dir = DATA_PATH.'/fever';
@mkdir(\$dir, 0755, true);
chown(\$dir, 'www-data');
\$keyHash = sha1(\$salt);
\$keyFile = \$dir.'/.key-'.\$keyHash.'-'.\$feverKey.'.txt';
file_put_contents(\$keyFile, '${user}');
chown(\$keyFile, 'www-data');
echo '✅ Fever key configured for ${user}' . PHP_EOL;
" 2>/dev/null
}

# Run original FreshRSS entrypoint (handles install, user creation, permissions)
# We replace ourselves with it at the end, but first we intercept to add Fever setup.
# Strategy: source the entrypoint logic up to the exec, then do our setup, then exec.

# Run the original entrypoint in a subshell (it will exec apache, so we must fork)
# Instead: call original entrypoint as a pre-hook only for setup, then exec apache ourselves.

# Actually: run entrypoint.sh but override the final exec by trapping it.
# Simplest correct approach: just exec the original entrypoint but inject a background waiter.

if [ -n "$FRESHRSS_API_PASSWORD" ] && [ -n "$FRESHRSS_DEFAULT_USER" ]; then
    # Wait for user config to appear, then set up Fever (runs in background)
    (
        TRIES=0
        while [ $TRIES -lt 60 ]; do
            if [ -f "/var/www/FreshRSS/data/users/${FRESHRSS_DEFAULT_USER}/config.php" ]; then
                setup_fever "$FRESHRSS_DEFAULT_USER" "$FRESHRSS_API_PASSWORD"
                exit 0
            fi
            sleep 1
            TRIES=$((TRIES + 1))
        done
        echo "⚠️  Fever setup timed out: user config not found" >&2
    ) &
fi

# Hand off to original entrypoint (which will exec apache and block)
exec /var/www/FreshRSS/Docker/entrypoint.sh "$@"
