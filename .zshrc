alias create-password="openssl rand -base64 32 | tr -d '\n'"

# Easier rootless usage

## Service accounts
typeset -a service_users=(
    <LOCAL ACCOUNT HERE>
    <ANOTHER LOCAL ACCOUNT HERE>
    <ANOTHER LOCAL ACCOUNT HERE>
    <ANOTHER LOCAL ACCOUNT HERE>
    <...>
)

## Execute commands or open an interactive shell as a service user
_as_user() {
    local user="$1"
    shift

    local uid
    uid="$(id -u "$user")" || return

    local runtime_dir="/run/user/$uid"

    sudo -H -u "$user" \
        XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
        /usr/bin/zsh -c '
            if [[ ! -S "$XDG_RUNTIME_DIR/bus" ]]; then
                print -u2 "User systemd bus unavailable"
                exit 1
            fi

            cd || exit

            if (( $# )); then
                exec "$@"
            else
                exec /usr/bin/zsh -i
            fi
        ' _ "$@"
}

for user in "${service_users[@]}"; do
    eval "function ${user}() { _as_user ${user} \"\$@\"; }"
done

unset user
