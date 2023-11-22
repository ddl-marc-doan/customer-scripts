# set the pvc names from kubectl to compare later with awscli ebs volume output

namespace="domino-compute"  # Replace with your desired namespace
output_file="pvc_names_output.txt"  # Replace with the desired output file name

# Run the command and save the output to a variable
pvc_names_array=$(kubectl get pvc -n "$namespace" -o json | grep -o '"name": "[^"]*' | cut -d'"' -f4)

# Check if the variable is not empty before writing to the file
if [ -n "$pvc_names_array" ]; then
  # Use echo to print each element on a new line and save it to the output file
  echo "$pvc_names_array" > "$output_file"
  echo "PVC names have been saved to $output_file"
else
  echo "No PVC names found."
fi
