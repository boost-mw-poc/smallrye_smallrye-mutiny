#!/usr/bin/env just --justfile

# Do a quick build
quick-build:
    ./mvnw -Dquickly

# Run all the tests
verify:
    ./mvnw verify -Pparallel-tests -T8

# Prepare a release branch
prepare-release previousVersion version:
    @echo "🚀 Preparing a branch for releasing version {{version}}"
    git switch -c release/{{version}}
    yq -i '.release.current-version = "{{version}}"' .github/project.yml
    yq -i '.release.previous-version = "{{previousVersion}}"' .github/project.yml
    ./mvnw --batch-mode --no-transfer-progress versions:set -DnewVersion={{version}} -DgenerateBackupPoms=false
    ./mvnw --batch-mode --no-transfer-progress versions:set -DnewVersion={{version}} -DgenerateBackupPoms=false -pl bom
    jbang .build/UpdateDocsAttributesFiles.java --mutiny-version={{version}}
    ./mvnw --batch-mode --no-transfer-progress clean install -DskipTests
    ./mvnw --batch-mode --no-transfer-progress -Pupdate-workshop-examples -f workshop-examples compile -DworkshopVersion={{version}}
    find workshop-examples -name '*.java' | xargs chmod +x
    git commit -am "chore(release): update version metadata for Mutiny {{version}}"
    @echo "✅ All set, please review the changes on this branch before doing the release, then:"
    @echo "   - git push origin release/{{version}} --set-upstream"
    @echo "   - just perform-release"

# Perform a release
perform-release:
    #!/usr/bin/env bash
    export PREVIOUS_VERSION=$(yq '.release.previous-version' .github/project.yml)
    export RELEASE_VERSION=$(yq '.release.current-version' .github/project.yml)
    export NEXT_VERSION=$(yq '.release.next-version' .github/project.yml)
    echo "🚀 Releasing: ${PREVIOUS_VERSION} ➡️ ${RELEASE_VERSION} ➡️ ${NEXT_VERSION}"
    export JRELEASER_GITHUB_TOKEN=$(gh auth token)
    export JRELEASER_PROJECT_VERSION=${RELEASE_VERSION}
    export JRELEASER_TAG_NAME=${RELEASE_VERSION}
    export JRELEASER_PREVIOUS_TAG_NAME=${PREVIOUS_VERSION}
    export JRELEASER_BRANCH="release/${RELEASE_VERSION}"
    ./mvnw --batch-mode --no-transfer-progress -Pjreleaser jreleaser:changelog -pl :mutiny-project
    echo "✅ Release notes ok"
    gh release create ${RELEASE_VERSION} \
      --discussion-category 'Announcements' \
      --notes-file target/jreleaser/release/CHANGELOG.md \
      --target ${JRELEASER_BRANCH} \
      --prerelease --latest=false
    echo "✅ Release created"
    ./mvnw --batch-mode --no-transfer-progress versions:set -DnewVersion=${NEXT_VERSION} -DgenerateBackupPoms=false
    ./mvnw --batch-mode --no-transfer-progress versions:set -DnewVersion=${NEXT_VERSION} -DgenerateBackupPoms=false -pl bom
    git commit -am "chore(release): set development version to ${NEXT_VERSION}"
    just clear-revapi
    echo "✅ All set, don't forget to merge this branch and push upstream."
    echo "💡 If you released from main:"
    echo "      git switch main"
    echo "      git merge release/${RELEASE_VERSION}"
    echo "      git push"

# Clear RevAPI justifications
clear-revapi:
    #!/usr/bin/env bash
    jbang .build/CompatibilityUtils.java clear --version="${RELEASE_VERSION}" --do-not-clear-version-prefix="1."
    if [[ $(git diff --stat) != '' ]]; then
      git add -A
      git status
      git commit -m "chore(release): clear RevAPI breaking change justifications"
    else
      echo "No justifications cleared"
    fi