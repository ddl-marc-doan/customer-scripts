#!/bin/bash

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### Use this argument at the command line to do a dry run: --dry-run
### Example: sh delete_ebs.sh --dry-run
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###

dry_run=false
if [[ "$*" == *"--dry-run"* ]]; then
  dry_run=true
  echo -e "\n##########################\n##########################\nRunning in dry-run mode...\n##########################\n##########################"
fi


### ### ### ### ### ### ##
### Required Variables ###
### ### ### ### ### ### ##

namespace="domino-compute"
cluster_name="marcd-fm-istio"
# tag_key="KubernetesCluster"
tag_key="AssetID"
# tag_value="stevel19523"
tag_value="MSR03632"

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### ### SCRIPT 2 - READ IN TEXT FILE WITH KUBECTL VOLUME ELEMENTS ### ### #####
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###

# read in pvc names from a text file that we generate with SCRIPT 1 to compare later with awscli ebs volume output
# this is the kubectl command being read in: pvc_names_array=$(kubectl get pvc -n "$namespace" -o json | grep -o '"name": "[^"]*' | cut -d'"' -f4)

input_file="pvc_names_output.txt"  # Replace with the name of your input file

# Check if the input file exists
if [ -f "$input_file" ]; then
  # Read the file line by line and store the names in an array
  pvc_names_array=()
  while IFS= read -r line; do
    pvc_names_array3+=("$line")
  done < "$input_file"

  # Print the array to verify the names have been loaded
  for name in "${pvc_names_array[@]}"; do
    echo "$name"
  done
else
  echo "Input file '$input_file' does not exist."
fi

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### ### SCRIPT 2 - READ IN TEXT FILE WITH KUBECTL VOLUME ELEMENTS ### ### #####
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###

if [ "$dry_run" = false ]; then
    # Line to exclude in dry-run mode
    # This line will be executed when not in dry-run mode
    echo -e "\n#######################\n#######################\nWARNING: Script is LIVE\n#######################\n#######################"

    # Display the confirmation prompt
    echo "ARE YOU SURE? (yes/no)"

    # Read user input
    read response

    # Check if the user entered "yes" to confirm
    if [ "$response" == "yes" ]; then
        echo -e "\nWarning: Dry run NOT initiated - DELETION may take place\nThe script will start in 3 seconds" 
        sleep 3
    else
        echo "You did not confirm. Exiting program..."
        sleep 3
        exit 1
        # Handle the case where the user did not confirm
    fi
fi

# Look for available volumes in AWS/EBS (unattached / not bound)
ebs_values=$(aws ec2 describe-volumes \
    --filters "Name=status,Values=available" "Name=tag:kubernetes.io/cluster/$cluster_name,Values=owned" "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=$namespace" \
    --query "Volumes[*].Tags[?Key=='kubernetes.io/created-for/pvc/name'].Value" \
    --output json)
# ebs_values=$(aws ec2 describe-volumes \
#     --filters "Name=status,Values=available" "Name=tag:$tag_key,Values=$tag_value" "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=domino-compute" \
#     --query "Volumes[*].Tags[?Key=='kubernetes.io/created-for/pvc/name'].Value" \
#     --output json)

# Create ebs_values_array from the command output
# ebs_values_array=($(echo "$ebs_values" | jq -r '.[] | .[]'))
ebs_values_array=($(echo "$ebs_values" | awk -F'"' '/./ {print $2}'))


# Use "${ebs_values_array[@]}" to print all elements of the array
echo -e "\n\nEBS PVCs associated with cluster $cluster_name that are AVAILABLE in AWS: \n\n${ebs_values_array[@]}"
echo -e "\n\nKUBECTL PVCs that have a claim to a PV in-cluster: \n\n${pvc_names_array}"
echo -e "\n\n\n"

# Split the space-separated string into an array
IFS=$'\n' read -d '' -ra pvc_names_array <<< "$pvc_names_array"

# Assuming you have ebs_values_array and pvc_names_array

# Initialize an array to store elements in ebs_values_array that are not in pvc_names_array
elements_not_in_pvc_names=()

# Iterate through ebs_values_array
for ebs_value in "${ebs_values_array[@]}"; do
    found=false

    # Iterate through pvc_names_array to check if the element is present
    for pvc_name in "${pvc_names_array[@]}"; do
        if [[ "$ebs_value" == "$pvc_name" ]]; then
            found=true
            break
        fi
    done

    # If the element is not found in pvc_names_array, add it to the new array
    if [ "$found" == "false" ]; then
        elements_not_in_pvc_names+=("$ebs_value")
    fi
done

# Define the regex pattern
regex_pattern="^[A-Za-z0-9]{24}-[A-Za-z0-9]{5}$"

echo="\n\n\n"

# Iterate through the elements in elements_not_in_pvc_names
for element in "${elements_not_in_pvc_names[@]}"; do
    # Check if the element matches the regex pattern
    if [[ $element =~ $regex_pattern ]]; then
        # echo "Element '$element' matches the regex pattern."
        ebs_volume_to_be_deleted=$(aws ec2 describe-volumes \
            --filters "Name=status,Values=available" "Name=tag:KubernetesCluster,Values=$cluster_name" "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=domino-compute" \
            --query "Volumes[?Tags[?Key=='kubernetes.io/created-for/pvc/name' && Value=='$element']].VolumeId" \
            --output json | grep -o 'vol-[^"]*' | tr -d '[]"')

        ebs_creation_time=$(aws ec2 describe-volumes \
            --filters "Name=status,Values=available" "Name=tag:KubernetesCluster,Values=$cluster_name" "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=domino-compute" \
            --query "Volumes[?Tags[?Key=='kubernetes.io/created-for/pvc/name' && Value=='$element']].[CreateTime]" \
            --output text | tr -d ' [] ')

        ebs_size_tag=$(aws ec2 describe-volumes \
            --filters "Name=status,Values=available" "Name=tag:KubernetesCluster,Values=$cluster_name" "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=domino-compute" \
            --query "Volumes[?Tags[?Key=='kubernetes.io/created-for/pvc/name' && Value=='$element']].[Size]" \
            --output text | tr -d '[] ')


        if [ "$dry_run" == true ]; then
        # Line to exclude in dry-run mode
        # This line will be executed when not in dry-run mode

            echo -e "\n*******\nDRY RUN\n*******\n\nEBS Volumes that will be deleted with dry-run deactivated:\n"
            echo "Volume ID|PVC Name|Volume Creation time|Disk Size (GB)"
            echo -e "$ebs_volume_to_be_deleted|$element|$ebs_creation_time|$ebs_size_tag\n"
            # echo "Volume ID: $ebs_volume_to_be_deleted"
            # echo "PVC Name: $element"
            # echo "Volume creation time: $ebs_creation_time"
            # echo "Disk Size: $ebs_size_tag"
            
        fi

        ### DELETE VOLUME with --dry-run option

        # Conditional check to exclude a specific line when in dry-run mode
        if [ "$dry_run" = false ]; then
        # Line to exclude in dry-run mode
        # This line will be executed when not in dry-run mode
   
            echo "\nEBS Volume deletion: \n"
            echo "Volume ID: $ebs_volume_to_be_deleted"
            echo "PVC Name: $element"
            echo "Volume creation time: $ebs_creation_time"
            echo "Disk Size: $ebs_size_tag"
            aws ec2 delete-volume --volume-id $ebs_volume_to_be_deleted
            echo "EBS Volume deleted\n"
            sleep 5
        fi
        
    else
        echo "Element '$element' does not match a user execution (App, Workspace, or Batch Job)"
        # Add your action here for non-matching elements
    fi
done