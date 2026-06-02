#compdef qvm-launcher.sh

_qvm_launcher() {
    local -a vm_names
    vm_names=()
    while IFS= read -r -d '' dir; do
        if [ -f "${dir}/$(basename "${dir}").qcow2" ]; then
            vm_names+=("$(basename "${dir}")")
        fi
    done < <(find . -maxdepth 1 -type d ! -name ".*" ! -name ".git" -print0 2>/dev/null | sort -z)

    _arguments \
        '--list[list all available VMs]' \
        '--install-completion[install shell autocompletion]' \
        '(-f)--format[create disk and boot installer ISO]' \
        '(--format)-f[create disk and boot installer ISO]' \
        '*: :->args'

    case $state in
        args)
            if [[ $CURRENT -eq 2 ]]; then
                _describe 'VM name' vm_names
            elif [[ ${words[2]} == "-f" || ${words[2]} == "--format" ]]; then
                if [[ $CURRENT -eq 3 ]]; then
                    _describe 'VM name' vm_names
                elif [[ $CURRENT -eq 4 ]]; then
                    _files -g '*.iso'
                fi
            fi
            ;;
    esac
}

_qvm_launcher "$@"
