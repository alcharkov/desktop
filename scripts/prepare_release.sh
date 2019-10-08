#!/usr/bin/env bash

# exit when any command fails
set -e

function writeError {
    echo "[ERROR  ] $@"
}
function writeWarning {
    echo "[WARNING] $@"
}
function writeInfo {
    echo "[INFO   ] $@"
}

# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

# mattermost repo might not be the origin one, we don't want to enforce that.
org="github.com:mattermost"
gitOrigin=`git remote -v | grep $org | grep push | awk '{print $1}'`

function tag {

    git tag -a "v${1}" -m "Desktop Version ${2}"
}

function branchNameFromVersion {
    $release_branch = "release-$1.$2"
    $release_tag = "v$1.$2.$3"
}

function writePackageVersion {
    tempfile=`mktemp -t "package.json"`
    jq ".version = \"${1}\"" ./package.json > $tempfile && mv $tempfile ./package.json
    git add ./package.json
    git commit -qm "Bump to version ${1}"
}

# get original git branch
branch_name=$(git symbolic-ref -q HEAD)
branch_name=${branch_name##refs/heads/}
branch_name=${branch_name:-HEAD}

dirty=`git diff --quiet && echo 0 || echo 1`
if [[ $dirty -eq 1 ]]; then
    msg="Please use this script on a clean branch"
    writeError $msg
    exit -10
fi

# TODO require jq, git

# get version
PKG_VERSION=`jq -r .version package.json`
# remove trailing
CURRENT_VERSION=${PKG_VERSION%-develop}
CURRENT_VERSION=${PKG_VERSION%-rc-*}
# parse version
IFS='.' read MAJOR MINOR MICRO <<<"$CURRENT_VERSION"
case $1 in
    "help")
        echo "todo"
    ;;
    "rc")
        if [[ $branch_name =~ "release-.*" ]]; then
            # RC=${PKG_VERSION#"*-rc-"}
            IFS='-rc-' read ignore RC <<<"$PKG_VERSION"
            case $RC in
            ''|*[!0-9]*) 
                msg="No release candidate on the version, assuming 0"
                writeWarning $msg
                RC=0
            ;;
            *)
                RC=$(( RC + 1 ))
            ;;
            esac
            msg="Generating ${CURRENT_VERSION} release candidate ${RC}"
            writeInfo $msg
            NEW_PKG_VERSION="${CURRENT_VERSION}-rc-${RC}"
            writePackageVersion "$NEW_PKG_VERSION"
            tagDescription="Release candidate ${RC}"
            tag $NEW_PKG_VERSION "$tagDescription"
            msg="locally created an rc. In order to build you'll have to"
            writeInfo $msg
            echo "$ git push --follow-tags ${gitOrigin} ${branch_name}:${branch_name}\n"
        else
            error="Can't generate a release candidate on a non release-X.Y branch"
            writeError $error
            exit -2

        fi
    ;;
    "final")
        if [[ $branch_name =~ "release-.*" ]]; then
            msg="Releasing v${CURRENT_VERSION}"
            writeInfo $msg
            NEW_PKG_VERSION=${CURRENT_VERSION}
            tagDescription="Released on `date -u`" 
            tag $NEW_PKG_VERSION $tagDescription
            msg="locally created a release. In order to build you'll have to:"
            writeInfo $msg
            echo "$ git push --follow-tags ${gitOrigin} ${branch_name}:${branch_name}"
            

        else
            error="Can't release on a non release-X.Y branch"
            writeError $error
            exit -2
        fi

    ;;
    "branch")
        # Quality releases should run from a release branch
        msg="current branch: ${branch_name}"
        writeInfo $msg
        if [[ $branch_name =~ release-.* ]]; then
            NEW_BRANCH_VERSION="${MAJOR}.$(( MINOR + 1 ))"
            NEW_BRANCH_NAME="release-${NEW_BRANCH_VERSION}"
            msg="Doing a quality branch: ${NEW_BRANCH_NAME}"
            writeInfo $msg

            if git show-ref --verify --quiet refs/heads/${NEW_BRANCH_NAME}; then
                error="branch ${NEW_BRANCH_NAME} exists"
                writeError $error
                exit -3
            fi

            NEW_PKG_VERSION="${NEW_BRANCH_VERSION}.0-rc-0"
            #git pull --ff-only $gitOrigin ${branch_name}
            git checkout -b "${NEW_BRANCH_NAME}"
            writePackageVersion "${NEW_PKG_VERSION}"
            tagDescription="Quality branch"
            tag "${NEW_PKG_VERSION}" "${tagDescription}"
            msg="locally created quality branch. In order to build you'll have to"
            writeInfo $msg
            echo "$ git push --follow-tags ${gitOrigin} ${NEW_BRANCH_NAME}:${NEW_BRANCH_NAME}"

        else
            if [[ $branch_name -ne "master" ]]; then
                msg="You are branching on ${branch_name} instead of master or a relase-branch"
                writeWarning $msg
                read -p "Do you wish to continue? [y/n]" -n 1 -r
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
            NEW_BRANCH_VERSION="${MAJOR}.${MINOR}"
            NEW_BRANCH_NAME="release-${NEW_BRANCH_VERSION}"
            NEW_PKG_VERSION="${NEW_BRANCH_VERSION}.0-rc-0"
            MASTER_PKG_VERSION="${MAJOR}.$(( MINOR + 2 )).0-develop"
            msg="Creating a new features branch: ${NEW_BRANCH_NAME}"
            writeInfo $msg

            if git show-ref --verify --quiet refs/heads/${NEW_BRANCH_NAME}; then
                error="branch ${NEW_BRANCH_NAME} exists"
                writeError $error
                exit -3
            fi

            git branch "${NEW_BRANCH_NAME}"
            msg="Writing new package version for development: ${MASTER_PKG_VERSION}"
            writeInfo $msg
            writePackageVersion "${MASTER_PKG_VERSION}"
            git checkout "${NEW_BRANCH_NAME}"
            writePackageVersion "${NEW_PKG_VERSION}"
            tagDescription="NewFeatures branch"
            tag "${NEW_PKG_VERSION}" "${tagDescription}"
            msg="Locally created new features branch. In order to build you'll have to"
            writeInfo $msg
            echo "$ git push --follow-tags ${gitOrigin} ${NEW_BRANCH_NAME}:${NEW_BRANCH_NAME}"
            echo "For writing master changes you'll need to:"
            echo "$ git push ${gitOrigin} ${branch_name}:${branch_name}"

        fi


    ;;
    *)
        writeError "Only branch|rc|final parameters are accepted"
        exit -1
    ;;
esac
exit 0
