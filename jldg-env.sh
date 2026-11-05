# Source this file in Bash or a POSIX shell; do not execute it.
# Set JLDG_HELPER_DIR before sourcing only for a nonstandard installation.
_jldg_helper_dir=${JLDG_HELPER_DIR:-/usr/local/jldg}
case :${PATH-}: in
    *:"$_jldg_helper_dir":*) ;;
    *) PATH=$_jldg_helper_dir${PATH:+:$PATH} ;;
esac
export PATH
JWT_USER_PATH='!jldg-token'
export JWT_USER_PATH
unset _jldg_helper_dir
