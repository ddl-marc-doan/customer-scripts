# Define the Docker registry URL and authentication
REGISTRY_URL="https://127.0.0.1:5000"
REGISTRY_USER="domino-registry"
REGISTRY_PASSWORD="PASSWORD"
# Get the list of repositories from the catalog
REPOSITORIES=$(curl -sk --user $REGISTRY_USER:$REGISTRY_PASSWORD $REGISTRY_URL/v2/_catalog | python3 -c "import sys, json; data = json.load(sys.stdin); print('\n'.join(data['repositories']))")
# Loop through each repository and get SHA256 digests
for repo in $REPOSITORIES; do
  # Get the list of tags for the repository
  TAGS=$(curl -sk --user $REGISTRY_USER:$REGISTRY_PASSWORD $REGISTRY_URL/v2/$repo/tags/list | python3 -c "import sys, json; data = json.load(sys.stdin); print('\n'.join(data['tags']))")
  # Loop through each tag and get the SHA256 digest
  for tag in $TAGS; do
    # Query the registry API to get the manifest
    MANIFEST_JSON=$(curl -sk --user $REGISTRY_USER:$REGISTRY_PASSWORD -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "$REGISTRY_URL/v2/$repo/manifests/$tag")
    # Extract the SHA256 digest from the manifest JSON
    DIGEST=$(echo "$MANIFEST_JSON" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data['config']['digest'])")
    LAYER_DATA=$(echo $MANIFEST_JSON | python3 -c "import sys,json; data = json.load(sys.stdin); layerdata = [x['digest'] for x in data['layers']]; layerstr = '|'.join(layerdata); print(layerstr)")
    if [ -n "$DIGEST" ]; then
      echo "Repository: $repo, Tag: $tag, Manifest Digest: $DIGEST, Layer Digests: $LAYER_DATA"
    else
      echo "Error retrieving digest for Repository: $repo, Tag: $tag"
    fi
  done
done
