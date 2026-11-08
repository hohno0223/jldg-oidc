# Source this file in tcsh; do not execute it.
# Set JLDG_HELPER_DIR before sourcing only for a nonstandard installation.
set _jldg_helper_dir = "/usr/local/jldg"
if ( $?JLDG_HELPER_DIR ) then
    if ( "$JLDG_HELPER_DIR" != "" ) then
        set _jldg_helper_dir = "$JLDG_HELPER_DIR"
    endif
endif
set _jldg_path_found = 0
foreach _jldg_path_entry ( $path:q )
    if ( "$_jldg_path_entry" == "$_jldg_helper_dir" ) then
        set _jldg_path_found = 1
    endif
end
if ( $_jldg_path_found == 0 ) then
    set path = ( "$_jldg_helper_dir" $path:q )
endif
setenv JWT_USER_PATH "\!jldg-auth --token"
unset _jldg_helper_dir _jldg_path_found _jldg_path_entry
