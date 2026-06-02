#compdef qvm-launcher.sh

_qvm_launcher() {
    local expl
    # Find all VM directories (subdirs with matching .qcow2 file)
    local -a vm_names
    vm_names=()
    while IFS= read -r -d '' dir; do
        if [ -f "${dir}/$(basename "${dir}").qcow2" ]; then
            vm_names+=("$(basename "${dir}")")
        fi
    done < <(find . -maxdepth 1 -type d ! -name ".*" ! -name ".git" -print0 2>/dev/null | sort -z)

    _arguments '1: :->vmname' '*::arg:->args'

    case $state in
        vmname)
            _describe 'VM name' vm_names
            ;;
        arg)
            case $line[1] in
                -f|--format)
                    _describe 'VM name' vm_names
                    ;;
            esac
            ;;
    esac
}

_qvm_launcher "$@"