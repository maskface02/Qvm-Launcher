# Bash completion for QVM Launcher
# To enable, copy this file to your bash completion directory:
#   sudo cp qvm-completion.bash /etc/bash_completion.d/qvm-launcher
# Or source it manually: source qvm-completion.bash

_qvm_launcher() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    _get_vm_names() {
        local -n _result=$1
        _result=()
        local dir
        while IFS= read -r -d '' dir; do
            if [ -f "${dir}/$(basename "${dir}").qcow2" ]; then
                _result+=("$(basename "${dir}")")
            fi
        done < <(find . -maxdepth 1 -type d ! -name ".*" ! -name ".git" -print0 2>/dev/null | sort -z)
    }

    case $COMP_CWORD in
        1)
            local flags="-f --format --list --install-completion"
            local vm_dirs=()
            _get_vm_names vm_dirs
            COMPREPLY=( $(compgen -W "${flags} ${vm_dirs[*]}" -- "$cur") )
            ;;
        2)
            if [[ "$prev" == "-f" || "$prev" == "--format" ]]; then
                local vm_dirs=()
                _get_vm_names vm_dirs
                COMPREPLY=( $(compgen -W "${vm_dirs[*]}" -- "$cur") )
            fi
            ;;
        3)
            if [[ "${COMP_WORDS[1]}" == "-f" || "${COMP_WORDS[1]}" == "--format" ]]; then
                local IFS=$'\n'
                COMPREPLY=( $(compgen -f -- "$cur" | grep -i '\.iso$'; compgen -d -- "$cur") )
            fi
            ;;
    esac
}

# Register the completion function
complete -F _qvm_launcher qvm-launcher-sdl.sh
