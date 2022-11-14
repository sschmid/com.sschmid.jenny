#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PROJECT="Jenny"
PACKAGE_PREFIX="com.sschmid"
FILES=(README.md CHANGELOG.md LICENSE.md)
declare -A PROJECTS=(
  [Jenny]=Editor
  [Jenny.Generator]=Editor
  [Jenny.Generator.Unity.Editor]=Editor
  [Jenny.Plugins]=Editor
  [Jenny.Plugins.Unity]=Editor
)

get_dependencies() {
  local -i upm=0 include_transitive=1
  local options

  while (($#)); do case "$1" in
    --unity-package) shift; upm=1; unset include_transitive; options="--unity-package" ;;
    --) shift; break ;; *) break ;;
  esac done

  local reference reference_csproj
  while read -r reference; do
    reference="$(basename "${reference}" .csproj)"
    reference_csproj="${PROJECT}/src/${reference}/${reference}.csproj"
    ((upm)) && reference="${PACKAGE_PREFIX}.${reference,,}"
    echo -e "${reference}\t$(xmllint --xpath 'string(/Project/PropertyGroup/Version)' "${reference_csproj}")"
    ((upm)) || get_dependencies ${options:+"${options}"} "${reference_csproj}"
  done < <(dotnet list "$1" reference | tail -n +3)

  dotnet restore "$1" > /dev/null
  local package indent
  while read -r package; do
    indent="$(echo "${package}" | awk '{print $1}')"
    if [[ "${indent}" == ">" ]]; then
      package="$(echo "${package}" | awk '{print $2 "\t" $(NF)}')"
      if [[ "${package}" != System* ]]; then
        ((upm)) && package="${PACKAGE_PREFIX}.${package,,}"
        echo "${package}"
      fi
    fi
  done < <(dotnet list "$1" package ${include_transitive:+--include-transitive} --highest-minor -v quiet)
}

update() {
  echo "Update ${project}"
  find "${dist}" -type f ! -name '*.meta' -delete
  rsync \
    --archive \
    --recursive \
    --prune-empty-dirs \
    --exclude="*.csproj" \
    --exclude="obj/" \
    "${src}/" "${dist}/${package_folder}"
}

generate_asmdef() {
  echo "Generate ${project}.asmdef"
  local name version dependencies="" platforms
  while read -r name version; do
    dependencies+="\n    \"${name}\","
  done < <(get_dependencies "${csproj}" | sort -u)
  if [[ -n "${dependencies}" ]]
  then dependencies="[ ${dependencies::-1}\n  ]"
  else dependencies="[]"
  fi
  if [[ "${package_folder}" == "Editor" ]]
  then platforms='"Editor"'
  else platforms=""
  fi

  cat << EOF > "${dist}/${package_folder}/${project}.asmdef"
{
  "name": "${project}",
  "rootNamespace": "${project}",
  "references": $(echo -e "${dependencies}"),
  "includePlatforms": [${platforms}],
  "excludePlatforms": [],
  "allowUnsafeCode": false,
  "overrideReferences": false,
  "precompiledReferences": [],
  "autoReferenced": true,
  "defineConstraints": [],
  "versionDefines": [],
  "noEngineReferences": false
}
EOF
}

generate_package_json() {
  echo "Generate ${project} package.json"
  local name version dependencies=""
  while read -r name version; do
    [[ "${version}" =~ ^[[:digit:]]*\.\* ]] && version="${version%%.*}.0.0"
    dependencies+="\n    \"${name}\": \"${version}\","
    openupm add "${name}" || true
  done < <(get_dependencies --unity-package "${csproj}" | sort -u)
  if [[ -n "${dependencies}" ]]
  then dependencies="{ ${dependencies::-1}\n  }"
  else dependencies="{ }"
  fi

  cat << EOF > "${dist}/package.json"
{
  "name": "${PACKAGE_PREFIX}.${project,,}",
  "version": "$(xmllint --xpath 'string(/Project/PropertyGroup/Version)' "${csproj}")",
  "displayName": "${project}",
  "description": "A lovely .NET Code Generator",
  "unity": "2021.3",
  "documentationUrl": "https://github.com/sschmid/Jenny",
  "changelogUrl": "https://github.com/sschmid/Jenny/blob/main/CHANGELOG.md",
  "licensesUrl": "https://github.com/sschmid/Jenny/blob/main/LICENSE.md",
  "dependencies": $(echo -e "${dependencies}"),
  "keywords": [
    "unity",
    "dotnet",
    "code-generation"
  ],
  "author": {
    "name": "sschmid"
  }
}
EOF
}

copy_files() {
  echo "Copy files"
  for file in "${FILES[@]}" ; do
    cp "${PROJECT}/${file}" "${dist}"
  done
}

main() {
  local project="$1"
  package_folder="${PROJECTS["${project}"]}"
  src="${PROJECT}/src/${project}"
  dist="Packages/${PACKAGE_PREFIX}.${project,,}"
  mkdir -p "${dist}/${package_folder}"
  csproj="${src}/${project}.csproj"
  update
  generate_asmdef
  generate_package_json
  copy_files
}

main "$@"
