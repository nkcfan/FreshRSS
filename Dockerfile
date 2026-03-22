# FreshRSS with multi-category support
# Extends official freshrss/freshrss image, overlaying only the modified files.

FROM freshrss/freshrss:edge

LABEL org.opencontainers.image.title="FreshRSS Multi-Category" \
      org.opencontainers.image.description="FreshRSS with multi-category feed support (issue #1989)" \
      org.opencontainers.image.source="https://github.com/nkcfan/freshrss" \
      org.opencontainers.image.url="https://github.com/nkcfan/freshrss"

# Copy only the modified files over the base image
COPY app/Models/CategoryDAO.php      /var/www/FreshRSS/app/Models/CategoryDAO.php
COPY app/Models/Feed.php             /var/www/FreshRSS/app/Models/Feed.php
COPY app/Models/FeedDAO.php          /var/www/FreshRSS/app/Models/FeedDAO.php
COPY app/SQL/install.sql.mysql.php   /var/www/FreshRSS/app/SQL/install.sql.mysql.php
COPY app/SQL/install.sql.pgsql.php   /var/www/FreshRSS/app/SQL/install.sql.pgsql.php
COPY app/SQL/install.sql.sqlite.php  /var/www/FreshRSS/app/SQL/install.sql.sqlite.php
COPY app/Services/ImportService.php  /var/www/FreshRSS/app/Services/ImportService.php
COPY p/api/fever.php                 /var/www/FreshRSS/p/api/fever.php

# Entrypoint wrapper: auto-configures Fever API key on first start
COPY Docker/entrypoint-wrapper.sh /entrypoint-wrapper.sh

RUN chown www-data:www-data \
      /var/www/FreshRSS/app/Models/CategoryDAO.php \
      /var/www/FreshRSS/app/Models/Feed.php \
      /var/www/FreshRSS/app/Models/FeedDAO.php \
      /var/www/FreshRSS/app/SQL/install.sql.mysql.php \
      /var/www/FreshRSS/app/SQL/install.sql.pgsql.php \
      /var/www/FreshRSS/app/SQL/install.sql.sqlite.php \
      /var/www/FreshRSS/app/Services/ImportService.php \
      /var/www/FreshRSS/p/api/fever.php && \
    chmod +x /entrypoint-wrapper.sh

ENTRYPOINT ["/entrypoint-wrapper.sh"]
# Preserve the base image CMD (Docker doesn't inherit CMD when ENTRYPOINT is overridden)
CMD ["/bin/bash", "-o", "pipefail", "-c", "([ -z \"$CRON_MIN\" ] || cron) && . /etc/apache2/envvars && exec apache2 -D FOREGROUND"]
