remove_route() {
    routes=$(find . -path "*/fabric8/route.yml")
    if [ ${#routes[@]} != 0 ]; then
        for file in ${routes[@]}
        do
            rm ${file}
        done
        if [[ $(git status --porcelain) ]]; then
            local -r branchName="remove-route"
            git checkout -b "${branchName}" > /dev/null 2> /dev/null

            commit "SB-782: Remove now unneeded route.yml"
            local -r pr=$(hub pull-request -f -p -h snowdrop:"${branchName}" -m "SB-782: Removal of unneeded route.yml")
            simple_log "Created PR: ${YELLOW}${pr}"
        else
            # if no changes were made it means that templates don't contain tokens and should be fixed
            log_ignored "No route.yml was found"
            return 1
        fi
    fi
}
