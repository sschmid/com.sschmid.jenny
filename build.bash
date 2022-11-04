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

get_project_references() {
  local reference
  while read -r reference; do
    reference="$(basename "${reference}" .csproj)"
    echo "${reference}"
    get_project_references "${PROJECT}/src/${reference}/${reference}.csproj"
  done < <(dotnet list "$1" reference | tail -n +3)
}

get_project_packages() {
  dotnet restore "$1" > /dev/null
  local package
  while read -r package; do
    [[ -z "${package}" ]] || echo "${package}"
  done < <(dotnet list "$1" package -v quiet | tail -n +4 | awk '{print $2}')
}

get_unity_dependencies() {
  local reference
  while read -r reference; do
    reference="$(basename "${reference}" .csproj)"
    echo -e "${PACKAGE_PREFIX}.${reference,,}\t$(xmllint --xpath 'string(/Project/PropertyGroup/Version)' "${PROJECT}/src/${reference}/${reference}.csproj")"
    get_unity_dependencies "${PROJECT}/src/${reference}/${reference}.csproj"
  done < <(dotnet list "$1" reference | tail -n +3)

  dotnet restore "$1" > /dev/null
  local package
  while read -r package; do
    [[ -z "${package}" ]] || echo "${PACKAGE_PREFIX}.${package,,}"
  done < <(dotnet list "$1" package -v quiet | tail -n +4 | awk '{print $2 "\t" $3}')
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
  local -a references packages project_dependencies
  local dependencies platforms
  dotnet restore "${csproj}" > /dev/null
  mapfile -t references < <(get_project_references "${csproj}" | sort -u)
  mapfile -t packages < <(get_project_packages "${csproj}" | sort -u)
  project_dependencies=("${references[@]}" "${packages[@]}")
  dependencies=""
  for dependency in "${project_dependencies[@]}"; do
    dependencies+=", \"${dependency}\""
  done
  if [[ "${package_folder}" == "Editor" ]]
  then platforms='"Editor"'
  else platforms=""
  fi

  cat <<EOF >"${dist}/${package_folder}/${project}.asmdef"
{
  "name": "${project}",
  "rootNamespace": "${project}",
  "references": [${dependencies:2}],
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
  local name version dependency_json=""
  while read -r name version; do
    dependency_json+="\n    \"${name}\": \"${version}\","
  done < <(get_unity_dependencies "${csproj}" | sort -u)
  if [[ -n "${dependency_json}" ]]
  then dependency_json="{ ${dependency_json::-1}\n  }"
  else dependency_json="{ }"
  fi

  cat <<EOF >"${dist}/package.json"
{
  "name": "${PACKAGE_PREFIX}.${project,,}",
  "version": "$(xmllint --xpath 'string(/Project/PropertyGroup/Version)' "${csproj}")",
  "displayName": "${project}",
  "description": "A lovely .NET Code Generator",
  "unity": "2021.3",
  "documentationUrl": "https://github.com/sschmid/Jenny",
  "changelogUrl": "https://github.com/sschmid/Jenny/blob/main/CHANGELOG.md",
  "licensesUrl": "https://github.com/sschmid/Jenny/blob/main/LICENSE.md",
  "dependencies": $(echo -e "${dependency_json}"),
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
