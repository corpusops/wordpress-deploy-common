#!/bin/bash
set -e
SDEBUG=${SDEBUG-}
SCRIPTSDIR="$(dirname $(readlink -f "$0"))"
cd "$SCRIPTSDIR/.."
TOPDIR=$(pwd)

# now be in stop-on-error mode
set -e
# load locales & default env
# load this first as it resets $PATH
for i in /etc/environment /etc/default/locale;do
    if [ -e $i ];then . $i;fi
done

# load virtualenv if any
for VENV in ./venv ../venv;do
    if [ -e $VENV ];then . $VENV/bin/activate;break;fi
done

PROJECT_DIR=$TOPDIR
if [ -e $TOPDIR/public_html ];then
    PROJECT_DIR=$TOPDIR/public_html
fi
export PROJECT_DIR
# activate shell debug if SDEBUG is set
if [[ -n $SDEBUG ]];then set -x;fi

DEFAULT_IMAGE_MODE=apache
export IMAGE_MODE=${IMAGE_MODE:-${DEFAULT_IMAGE_MODE}}
export WORDPRESS_FLAVOR=${WORDPRESS_FLAVOR:-apache}

NO_CHOWN=${NO_CHOWN-}
export APACHE_CONF_DIR="${APACHE_CONF_DIR:-"/etc/apache2"}"
# French legal http logs retention  is 3 years
export DOC_ROOT="${DOC_ROOT:-"${TOPDIR}/public_html"}"
export NO_SSL=${NO_SSL-1}
export SSL_CERT_BASENAME="${SSL_CERT_BASENAME:-"cert"}"
export APACHE_SKIP_CHECK="${APACHE_SKIP_CHECK-}"
export APACHE_ROTATE=${APACHE_ROTATE-$((365*3))}
export APACHE_USER=${APACHE_USER-"www-data"}
export APACHE_GROUP=${APACHE_GROUP-"www-data"}
export APACHE_LOGS_DIR="${APACHE_LOGS_DIR:-"/var/log/apache"}"
export APACHE_LOGS_DIRS="/logs /log $APACHE_LOGS_DIR"
IMAGE_MODES="(apache|fg)"
NO_START=${NO_START-}
WORDPRESS_CONF_PREFIX="${WORDPRESS_CONF_PREFIX:-"WORDPRESS__"}"
DEFAULT_NO_MIGRATE=
DEFAULT_NO_STARTUP_LOGS=
DEFAULT_NO_COLLECT_STATIC=
if [[ -n $@ ]];then
    DEFAULT_NO_STARTUP_LOGS=1
fi
NO_STARTUP_LOGS=${NO_MIGRATE-$DEFAULT_NO_STARTUP_LOGS}
NO_MIGRATE=${NO_MIGRATE-$DEFAULT_NO_MIGRATE}
DEFAULT_NO_IMAGE_SETUP=1
NO_IMAGE_SETUP="${NO_IMAGE_SETUP-}"
FORCE_IMAGE_SETUP="${FORCE_IMAGE_SETUP:-"1"}"
DO_IMAGE_SETUP_MODES="${DO_IMAGE_SETUP_MODES:-"fg|apache"}"
FINDPERMS_PERMS_DIRS_CANDIDATES="${FINDPERMS_PERMS_DIRS_CANDIDATES:-"/logs"}"
FINDPERMS_OWNERSHIP_DIRS_CANDIDATES="${FINDPERMS_OWNERSHIP_DIRS_CANDIDATES:-"public_html"}"
export APP_TYPE=wordpress
export APP_USER=www-data
export APP_GROUP=www-data
export USER_DIRS=". public_html"
SHELL_USER=${SHELL_USER:-${APP_USER}}

log() {
    echo "$@" >&2;
}

vv() {
    log "$@";"$@";
}

# Regenerate egg-info & be sure to have it in site-packages
regen_egg_info() {
    local f="$1"
    if [ -e "$f" ];then
        local e="$(dirname "$f")"
        echo "Reinstalling egg-info in: $e" >&2
        ( cd "$e" && gosu $APP_USER python setup.py egg_info >/dev/null 2>&1; )
    fi
}

#  shell: Run interactive shell inside container
_shell() {
    local pre=""
    local user="$APP_USER"
    if [[ -n $1 ]];then user=$1;shift;fi
    local bargs="$@"
    local NO_VIRTUALENV=${NO_VIRTUALENV-}
    local NO_NVM=${NO_VIRTUALENV-}
    local NVMRC=${NVMRC:-.nvmrc}
    local NVM_PATH=${NVM_PATH:-..}
    local NVM_PATHS=${NVMS_PATH:-${NVM_PATH}}
    local VENV_NAME=${VENV_NAME:-venv}
    local VENV_PATHS=${VENV_PATHS:-./$VENV_NAME ../$VENV_NAME}
    local DOCKER_SHELL=${DOCKER_SHELL-}
    local pre="DOCKER_SHELL=\"$DOCKER_SHELL\";touch \$HOME/.control_bash_rc;
    if [ \"x\$DOCKER_SHELL\" = \"x\" ];then
        if ( bash --version >/dev/null 2>&1 );then \
            DOCKER_SHELL=\"bash\"; else DOCKER_SHELL=\"sh\";fi;
    fi"
    if [[ -z "$NO_NVM" ]];then
        if [[ -n "$pre" ]];then pre=" && $pre";fi
        pre="for i in $NVM_PATHS;do \
        if [ -e \$i/$NVMRC ] && ( nvm --help > /dev/null );then \
            printf \"\ncd \$i && nvm install \
            && nvm use && cd - && break\n\">>\$HOME/.control_bash_rc; \
        fi;done $pre"
    fi
    if [[ -z "$NO_VIRTUALENV" ]];then
        if [[ -n "$pre" ]];then pre=" && $pre";fi
        pre="for i in $VENV_PATHS;do \
        if [ -e \$i/bin/activate ];then \
            printf \"\n. \$i/bin/activate\n\">>\$HOME/.control_bash_rc && break;\
        fi;done $pre"
    fi
    if [[ -z "$bargs" ]];then
        bargs="$pre && if ( echo \"\$DOCKER_SHELL\" | grep -q bash );then \
            exec bash --init-file \$HOME/.control_bash_rc -i;\
            else . \$HOME/.control_bash_rc && exec sh -i;fi"
    else
        bargs="$pre && . \$HOME/.control_bash_rc && \$DOCKER_SHELL -c \"$bargs\""
    fi
    export TERM="$TERM"; export COLUMNS="$COLUMNS"; export LINES="$LINES"
    exec gosu $user sh $( if [[ -z "$bargs" ]];then echo "-i";fi ) -c "$bargs"
}

#  configure: generate configs from template at runtime
configure() {
    if [[ -n $NO_CONFIGURE ]];then return 0;fi
    for i in $USER_DIRS;do
        if [ ! -e "$i" ];then mkdir -p "$i" >&2;fi
        chown $APP_USER:$APP_GROUP "$i"
    done
    if (find /etc/sudoers* -type f >/dev/null 2>&1);then chown -Rf root:root /etc/sudoers*;fi

    # copy only if not existing template configs from common deploy project
    # and only if we have that common deploy project inside the image
    if [ ! -e etc ];then mkdir etc;fi
    for i in local/*deploy-common/etc local/*deploy-common/sys/etc sys/etc;do
        if [ -d $i ];then cp -rfnv $i/* etc >&2;fi
    done
    # install wtih envsubst any template file to / (eg: logrotate & cron file)
    for i in $(find etc -name "*.envsubst" -type f 2>/dev/null);do
        di="/$(dirname $i)" \
            && if [ ! -e "$di" ];then mkdir -pv "$di" >&2;fi \
            && cp "$i" "/$i" \
            && CONF_PREFIX="$WORDPRESS_CONF_PREFIX" confenvsubst.sh "/$i" \
            && rm -f "/$i"
    done
    # install wtih frep any template file to / (eg: logrotate & cron file)
    for i in $(find etc -name "*.frep" -type f 2>/dev/null);do
        d="$(dirname "$i")/$(basename "$i" .frep)" \
            && di="/$(dirname $d)" \
            && if [ ! -e "$di" ];then mkdir -pv "$di" >&2;fi \
            && echo "Generating with frep $i:/$d" >&2 \
            && frep "$i:/$d" --overwrite
    done
    if [[ "$WORDPRESS_FLAVOR" = "apache" ]];then
        a2enmod remoteip deflate headers proxy proxy_http ssl rewrite
    fi
}

#  services_setup: when image run in daemon mode: pre start setup
#               like database migrations, etc
services_setup() {
    if [[ -z $NO_IMAGE_SETUP ]];then
        if [[ -n $FORCE_IMAGE_SETUP ]] || ( echo $IMAGE_MODE | egrep -q "$DO_IMAGE_SETUP_MODES" ) ;then
            : "continue services_setup"
        else
            log "No image setup"
            return 0
        fi
    else
        if [[ -n $SDEBUG ]];then
            log "Skip image setup"
            return 0
        fi
    fi
    DEFAULT_DH_FILE="/certs/dhparams.pem"
    if [[ "$WORDPRESS_FLAVOR" = "apache" ]];then
        APACHE_CONFIGS="${APACHE_CONFIGS:-"$(find /etc/apache2 -type f)"}"
        if ! (egrep -r -q "DHParameters" $APACHE_CONFIGS);then
            DEFAULT_DH_FILE=""
        fi
    fi
    # configure wp-config.php
    ( docker-entrypoint.sh sh -c 'echo wordpress configuration done >&2' )
    # alpine linux has /etc/crontabs/ and ubuntu based vixie has /etc/cron.d/
    if [ -e /etc/cron.d ] && [ -e /etc/crontabs ];then cp -fv /etc/crontabs/* /etc/cron.d >&2;fi
    # Run any migration
    if [[ -z ${NO_MIGRATE} ]];then
        ( cd $PROJECT_DIR \
            && gosu $APP_USER echo "migrate wordpress is a noop" )
    fi
    if [[ "$WORDPRESS_FLAVOR" = "apache" ]];then
        for e in $APACHE_LOGS_DIRS $APACHE_CONF_DIR;do
            if [ ! -e "$e" ];then mkdir -p "$e";fi
            if [ "x$NO_CHOWN" != "x" ] && [ -e "$e" ];then chown "$APACHE_USER" "$e";fi
        done
    fi
    export DH_FILE=${DH_FILE:-"$DEFAULT_DH_FILE"}
    if [ "x$NO_SSL" != "x" ];then
        log "no ssl setup"
    else
        cops_gen_cert.sh
        if !(openssl version >/dev/null 2>&1);then
            log "try to install openssl"
            WANT_UPDATE="1" cops_pkgmgr_install.sh openssl
        fi
        if [ "x$DH_FILE" != "x" ];then
            if [ ! -e "$DH_FILE" ];then
                ddhparams=$(dirname $DH_FILE)
                if [ ! -e "$ddhparams" ];then mkdir -pv "$ddhparams";fi
                openssl dhparam -out "$DH_FILE" 2048
                chmod 644 "$DH_FILE"
            fi
        fi
    fi
}

fixperms() {
    if [[ -n $NO_FIXPERMS ]];then return 0;fi
    for i in /etc/{crontabs,cron.d} /etc/logrotate.d /etc/supervisor.d;do
        if [ -e $i ];then
            while read f;do
                chown -R root:root "$f"
                chmod 0640 "$f"
            done < <(find "$i" -type f)
        fi
    done
    while read f;do chmod 0755 "$f";done < \
        <(find $FINDPERMS_PERMS_DIRS_CANDIDATES -type d \
          -not \( -perm 0755 2>/dev/null\) |sort)
    while read f;do chmod 0644 "$f";done < \
        <(find $FINDPERMS_PERMS_DIRS_CANDIDATES -type f \
          -not \( -perm 0644 2>/dev/null\) |sort)
    while read f;do chown $APP_USER:$APP_USER "$f";done < \
        <(find $FINDPERMS_OWNERSHIP_DIRS_CANDIDATES \
          \( -type d -or -type f \) \
             -and -not \( -user $APP_USER -and -group $APP_GROUP \)  2>/dev/null|sort)
}

#  usage: print this help
usage() {
    drun="docker run --rm -it <img>"
    echo "EX:
$drun [-e NO_MIGRATE=1] [ -e FORCE_IMAGE_SETUP] [-e IMAGE_MODE=\$mode]
    docker run <img>
        run either wordpress, cron, or celery beat|worker daemon
        (IMAGE_MODE: $IMAGE_MODES)

$drun \$args: run commands with the context ignited inside the container
$drun [ -e FORCE_IMAGE_SETUP=1] [ -e NO_IMAGE_SETUP=1] [-e SHELL_USER=\$ANOTHERUSER] [-e IMAGE_MODE=\$mode] [\$command[ \args]]
    docker run <img> \$COMMAND \$ARGS -> run command
    docker run <img> shell -> interactive shell
(default user: $SHELL_USER)
(default mode: $IMAGE_MODE)

If FORCE_IMAGE_SETUP is set: run migrate/collect static
If NO_IMAGE_SETUP is set: migrate/collect static is skipped, no matter what
If NO_START is set: start an infinite loop doing nothing (for dummy containers in dev)
"
  exit 0
}

do_fg() {
    ( cd $PROJECT_DIR \
        && exec docker-entrypoint.sh apache2-foreground )
}

if ( echo $1 | egrep -q -- "--help|-h|help" );then
    usage
fi

if [[ -n ${NO_START-} ]];then
    while true;do echo "start skipped" >&2;sleep 65535;done
    exit $?
fi

# Run app
pre() {
    configure
    services_setup
    fixperms
}

# only display startup logs when we start in daemon mode
# and try to hide most when starting an (eventually interactive) shell.
if [[ -n $NO_STARTUP_LOGS ]];then pre 2>/dev/null;else pre;fi

if [[ -z "$@" ]]; then
    if ! ( echo $IMAGE_MODE | egrep -q "$IMAGE_MODES" );then
        log "Unknown image mode ($IMAGE_MODES): $IMAGE_MODE"
        exit 1
    fi
    log "Running in $IMAGE_MODE mode"
    if [[ "$IMAGE_MODE" = "fg" ]]; then
        do_fg
    else
        cfg="/etc/supervisor.d/$IMAGE_MODE"
        if [ ! -e $cfg ];then
            log "Missing: $cfg"
            exit 1
        fi
        SUPERVISORD_CONFIGS="/etc/supervisor.d/logrotate /etc/supervisor.d/rsyslog $cfg" exec /bin/supervisord.sh
    fi
else
    if [[ "${1-}" = "shell" ]];then shift;fi
    ( cd $PROJECT_DIR && _shell $SHELL_USER "$@" )
fi
