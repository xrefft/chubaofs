# bash completion for cfs-cli                              -*- shell-script -*-

__cfs-cli_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__cfs-cli_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__cfs-cli_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__cfs-cli_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__cfs-cli_handle_go_custom_completion()
{
    __cfs-cli_debug "${FUNCNAME[0]}: cur is ${cur}, words[*] is ${words[*]}, #words[@] is ${#words[@]}"

    local out requestComp lastParam lastChar comp directive args

    # Prepare the command to request completions for the program.
    # Calling ${words[0]} instead of directly cfs-cli allows to handle aliases
    args=("${words[@]:1}")
    requestComp="${words[0]} __completeNoDesc ${args[*]}"

    lastParam=${words[$((${#words[@]}-1))]}
    lastChar=${lastParam:$((${#lastParam}-1)):1}
    __cfs-cli_debug "${FUNCNAME[0]}: lastParam ${lastParam}, lastChar ${lastChar}"

    if [ -z "${cur}" ] && [ "${lastChar}" != "=" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go method.
        __cfs-cli_debug "${FUNCNAME[0]}: Adding extra empty parameter"
        requestComp="${requestComp} \"\""
    fi

    __cfs-cli_debug "${FUNCNAME[0]}: calling ${requestComp}"
    # Use eval to handle any environment variables and such
    out=$(eval "${requestComp}" 2>/dev/null)

    # Extract the directive integer at the very end of the output following a colon (:)
    directive=${out##*:}
    # Remove the directive
    out=${out%:*}
    if [ "${directive}" = "${out}" ]; then
        # There is not directive specified
        directive=0
    fi
    __cfs-cli_debug "${FUNCNAME[0]}: the completion directive is: ${directive}"
    __cfs-cli_debug "${FUNCNAME[0]}: the completions are: ${out[*]}"

    if [ $((directive & 1)) -ne 0 ]; then
        # Error code.  No completion.
        __cfs-cli_debug "${FUNCNAME[0]}: received error from custom completion go code"
        return
    else
        if [ $((directive & 2)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __cfs-cli_debug "${FUNCNAME[0]}: activating no space"
                compopt -o nospace
            fi
        fi
        if [ $((directive & 4)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __cfs-cli_debug "${FUNCNAME[0]}: activating no file completion"
                compopt +o default
            fi
        fi

        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${out[*]}" -- "$cur")
    fi
}

__cfs-cli_handle_reply()
{
    __cfs-cli_debug "${FUNCNAME[0]}"
    local comp
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            while IFS='' read -r comp; do
                COMPREPLY+=("$comp")
            done < <(compgen -W "${allflags[*]}" -- "$cur")
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __cfs-cli_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __cfs-cli_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions=("${must_have_one_noun[@]}")
    elif [[ -n "${has_completion_function}" ]]; then
        # if a go completion function is provided, defer to that function
        completions=()
        __cfs-cli_handle_go_custom_completion
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    while IFS='' read -r comp; do
        COMPREPLY+=("$comp")
    done < <(compgen -W "${completions[*]}" -- "$cur")

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${noun_aliases[*]}" -- "$cur")
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
		if declare -F __cfs-cli_custom_func >/dev/null; then
			# try command name qualified custom func
			__cfs-cli_custom_func
		else
			# otherwise fall back to unqualified for compatibility
			declare -F __custom_func >/dev/null && __custom_func
		fi
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__cfs-cli_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__cfs-cli_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1 || return
}

__cfs-cli_handle_flag()
{
    __cfs-cli_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __cfs-cli_debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __cfs-cli_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __cfs-cli_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if [[ ${words[c]} != *"="* ]] && __cfs-cli_contains_word "${words[c]}" "${two_word_flags[@]}"; then
			  __cfs-cli_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__cfs-cli_handle_noun()
{
    __cfs-cli_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __cfs-cli_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __cfs-cli_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__cfs-cli_handle_command()
{
    __cfs-cli_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_cfs-cli_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __cfs-cli_debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__cfs-cli_handle_word()
{
    if [[ $c -ge $cword ]]; then
        __cfs-cli_handle_reply
        return
    fi
    __cfs-cli_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __cfs-cli_handle_flag
    elif __cfs-cli_contains_word "${words[c]}" "${commands[@]}"; then
        __cfs-cli_handle_command
    elif [[ $c -eq 0 ]]; then
        __cfs-cli_handle_command
    elif __cfs-cli_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __cfs-cli_handle_command
        else
            __cfs-cli_handle_noun
        fi
    else
        __cfs-cli_handle_noun
    fi
    __cfs-cli_handle_word
}

_cfs-cli_cluster_freeze()
{
    last_command="cfs-cli_cluster_freeze"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("false")
    must_have_one_noun+=("true")
    noun_aliases=()
}

_cfs-cli_cluster_info()
{
    last_command="cfs-cli_cluster_info"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_cluster_stat()
{
    last_command="cfs-cli_cluster_stat"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_cluster_threshold()
{
    last_command="cfs-cli_cluster_threshold"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_cluster()
{
    last_command="cfs-cli_cluster"

    command_aliases=()

    commands=()
    commands+=("freeze")
    commands+=("info")
    commands+=("stat")
    commands+=("threshold")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_compatibility_meta()
{
    last_command="cfs-cli_compatibility_meta"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_compatibility()
{
    last_command="cfs-cli_compatibility"

    command_aliases=()

    commands=()
    commands+=("meta")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("meta")
        aliashash["meta"]="meta"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_completion()
{
    last_command="cfs-cli_completion"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")
    local_nonpersistent_flags+=("--help")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_config_info()
{
    last_command="cfs-cli_config_info"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filter-status=")
    two_word_flags+=("--filter-status")
    local_nonpersistent_flags+=("--filter-status=")
    flags+=("--filter-writable=")
    two_word_flags+=("--filter-writable")
    local_nonpersistent_flags+=("--filter-writable=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_config_set()
{
    last_command="cfs-cli_config_set"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_config()
{
    last_command="cfs-cli_config"

    command_aliases=()

    commands=()
    commands+=("info")
    commands+=("set")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_datanode_decommission()
{
    last_command="cfs-cli_datanode_decommission"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_datanode_info()
{
    last_command="cfs-cli_datanode_info"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_datanode_list()
{
    last_command="cfs-cli_datanode_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filter-status=")
    two_word_flags+=("--filter-status")
    local_nonpersistent_flags+=("--filter-status=")
    flags+=("--filter-writable=")
    two_word_flags+=("--filter-writable")
    local_nonpersistent_flags+=("--filter-writable=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_datanode()
{
    last_command="cfs-cli_datanode"

    command_aliases=()

    commands=()
    commands+=("decommission")
    commands+=("info")
    commands+=("list")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_datapartition_add-replica()
{
    last_command="cfs-cli_datapartition_add-replica"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_datapartition_check()
{
    last_command="cfs-cli_datapartition_check"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_datapartition_decommission()
{
    last_command="cfs-cli_datapartition_decommission"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_datapartition_del-replica()
{
    last_command="cfs-cli_datapartition_del-replica"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_datapartition_info()
{
    last_command="cfs-cli_datapartition_info"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_datapartition()
{
    last_command="cfs-cli_datapartition"

    command_aliases=()

    commands=()
    commands+=("add-replica")
    commands+=("check")
    commands+=("decommission")
    commands+=("del-replica")
    commands+=("info")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_metanode_decommission()
{
    last_command="cfs-cli_metanode_decommission"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_metanode_info()
{
    last_command="cfs-cli_metanode_info"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_metanode_list()
{
    last_command="cfs-cli_metanode_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filter-status=")
    two_word_flags+=("--filter-status")
    local_nonpersistent_flags+=("--filter-status=")
    flags+=("--filter-writable=")
    two_word_flags+=("--filter-writable")
    local_nonpersistent_flags+=("--filter-writable=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_metanode()
{
    last_command="cfs-cli_metanode"

    command_aliases=()

    commands=()
    commands+=("decommission")
    commands+=("info")
    commands+=("list")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_metapartition_add-replica()
{
    last_command="cfs-cli_metapartition_add-replica"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_metapartition_check()
{
    last_command="cfs-cli_metapartition_check"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_metapartition_decommission()
{
    last_command="cfs-cli_metapartition_decommission"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_metapartition_del-replica()
{
    last_command="cfs-cli_metapartition_del-replica"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_metapartition_info()
{
    last_command="cfs-cli_metapartition_info"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_metapartition()
{
    last_command="cfs-cli_metapartition"

    command_aliases=()

    commands=()
    commands+=("add-replica")
    commands+=("check")
    commands+=("decommission")
    commands+=("del-replica")
    commands+=("info")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_user_create()
{
    last_command="cfs-cli_user_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--access-key=")
    two_word_flags+=("--access-key")
    local_nonpersistent_flags+=("--access-key=")
    flags+=("--password=")
    two_word_flags+=("--password")
    local_nonpersistent_flags+=("--password=")
    flags+=("--secret-key=")
    two_word_flags+=("--secret-key")
    local_nonpersistent_flags+=("--secret-key=")
    flags+=("--user-type=")
    two_word_flags+=("--user-type")
    local_nonpersistent_flags+=("--user-type=")
    flags+=("--yes")
    flags+=("-y")
    local_nonpersistent_flags+=("--yes")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_user_delete()
{
    last_command="cfs-cli_user_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--yes")
    flags+=("-y")
    local_nonpersistent_flags+=("--yes")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_user_info()
{
    last_command="cfs-cli_user_info"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_user_list()
{
    last_command="cfs-cli_user_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--keyword=")
    two_word_flags+=("--keyword")
    local_nonpersistent_flags+=("--keyword=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_user_perm()
{
    last_command="cfs-cli_user_perm"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_user_update()
{
    last_command="cfs-cli_user_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--access-key=")
    two_word_flags+=("--access-key")
    local_nonpersistent_flags+=("--access-key=")
    flags+=("--secret-key=")
    two_word_flags+=("--secret-key")
    local_nonpersistent_flags+=("--secret-key=")
    flags+=("--user-type=")
    two_word_flags+=("--user-type")
    local_nonpersistent_flags+=("--user-type=")
    flags+=("--yes")
    flags+=("-y")
    local_nonpersistent_flags+=("--yes")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_user()
{
    last_command="cfs-cli_user"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("info")
    commands+=("list")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("perm")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_volume_add-dp()
{
    last_command="cfs-cli_volume_add-dp"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_volume_create()
{
    last_command="cfs-cli_volume_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--capacity=")
    two_word_flags+=("--capacity")
    local_nonpersistent_flags+=("--capacity=")
    flags+=("--dp-size=")
    two_word_flags+=("--dp-size")
    local_nonpersistent_flags+=("--dp-size=")
    flags+=("--follower-read")
    local_nonpersistent_flags+=("--follower-read")
    flags+=("--mp-count=")
    two_word_flags+=("--mp-count")
    local_nonpersistent_flags+=("--mp-count=")
    flags+=("--replicas=")
    two_word_flags+=("--replicas")
    local_nonpersistent_flags+=("--replicas=")
    flags+=("--yes")
    flags+=("-y")
    local_nonpersistent_flags+=("--yes")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_volume_delete()
{
    last_command="cfs-cli_volume_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--yes")
    flags+=("-y")
    local_nonpersistent_flags+=("--yes")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_volume_info()
{
    last_command="cfs-cli_volume_info"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--data-partition")
    flags+=("-d")
    local_nonpersistent_flags+=("--data-partition")
    flags+=("--meta-partition")
    flags+=("-m")
    local_nonpersistent_flags+=("--meta-partition")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_cfs-cli_volume_list()
{
    last_command="cfs-cli_volume_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--keyword=")
    two_word_flags+=("--keyword")
    local_nonpersistent_flags+=("--keyword=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_volume_transfer()
{
    last_command="cfs-cli_volume_transfer"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("-f")
    local_nonpersistent_flags+=("--force")
    flags+=("--yes")
    flags+=("-y")
    local_nonpersistent_flags+=("--yes")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_volume()
{
    last_command="cfs-cli_volume"

    command_aliases=()

    commands=()
    commands+=("add-dp")
    commands+=("create")
    commands+=("delete")
    commands+=("info")
    commands+=("list")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("transfer")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("trans")
        aliashash["trans"]="transfer"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cfs-cli_root_command()
{
    last_command="cfs-cli"

    command_aliases=()

    commands=()
    commands+=("cluster")
    commands+=("compatibility")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("cptest")
        aliashash["cptest"]="compatibility"
    fi
    commands+=("completion")
    commands+=("config")
    commands+=("datanode")
    commands+=("datapartition")
    commands+=("metanode")
    commands+=("metapartition")
    commands+=("user")
    commands+=("volume")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("vol")
        aliashash["vol"]="volume"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()


    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_cfs-cli()
{
    local cur prev words cword
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __cfs-cli_init_completion -n "=" || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("cfs-cli")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local has_completion_function
    local last_command
    local nouns=()

    __cfs-cli_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_cfs-cli cfs-cli
else
    complete -o default -o nospace -F __start_cfs-cli cfs-cli
fi

# ex: ts=4 sw=4 et filetype=sh
