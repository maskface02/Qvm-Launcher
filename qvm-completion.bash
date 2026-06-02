# Bash completion for QVM Launcher
# To enable, copy this file to your bash completion directory:
#   sudo cp qvm-completion.bash /etc/bash_completion.d/qvm-launcher
# Or source it manually: source qvm-completion.bash

_qvm_launcher() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # If we're completing the first argument (command itself), don't do anything
    if [[ $COMP_CWORD -eq 1 ]]; then
        # Find all VM directories (subdirs with matching .qcow2 file)
        local vm_dirs=()
        while IFS= read -r -d '' dir; do
            if [ -f "${dir}/$(basename "${dir}").qcow2" ]; then
                vm_dirs+=("$(basename "${dir}")")
            fi
        done < <(find . -maxdepth 1 -type d ! -name ".*" ! -name ".git" -print0 2>/dev/null | sort -z)
        
        COMPREPLY=( $(compgen -W "${vm_dirs[*]}" -- "$cur") )
        return 0
    fi
    
    # If we're completing after -f, suggest VM names for new VM creation
    if [[ "$prev" == "-f" || "$prev" == "--format" ]]; then
        # Find all VM directories (subdirs with matching .qcow2 file)
        local vm_dirs=()
        while IFS= read -r -d '' dir; do
            if [ -f "${dir}/$(basename "${dir}").qcow2" ]; then
                vm_dirs+=("$(basename "${dir}")")
            fi
        done < <(find . -maxdepth 1 -type d ! -name ".*" ! -name ".git" -print0 2>/dev/null | sort -z)
        
        COMPREPLY=( $(compgen -W "${vm_dirs[*]}" -- "$cur") )
        return 0
    fi
    
    # If we're completing after the first arg and it's not a flag, we're likely specifying ISO
    # No completion for ISO files for now (could add if desired)
}

# Register the completion function
complete -F _qvm_launcher qvm-launcher.sh