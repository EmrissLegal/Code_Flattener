#!/bin/bash
# v3.4 - Automatically excludes the .git directory when using .gitignore.

# A script to generate a directory structure and a flattened content file from a folder.
#
# Enhancements in v3:
# 1. Asks user if they want to automatically exclude files/folders from .gitignore.
# 2. If yes, automatically excludes the .git directory.
# 3. Reads patterns from .gitignore if present and selected.
# 4. Asks for additional manual exclusions.
#
# Original Enhancements:
# 1. Prompts user to choose between generating only the structure file or both files.
# 2. Replaces restrictive top-level exclusion with a flexible pattern-based exclusion
#    that works for any file, directory, or glob pattern anywhere in the tree.

# Set locale to handle binary data and special characters safely.
export LC_ALL=C

# --- 1. SETUP ---
# Check if a folder path was provided as an argument.
if [ $# -eq 0 ]; then
  echo "Error: Please provide a folder path."
  echo "Usage: $0 /path/to/your/project"
  exit 1
fi

# Clean the provided folder path and get its base name.
folder_path="${1%/}"
folder_name=$(basename "$folder_path")
current_datetime=$(date +"%Y-%m-%d_%H-%M-%S")

# Define the output directory to be the same directory where the script is located.
script_dir=$(dirname "$0")
output_dir="$script_dir"

# Define the full paths for the output files.
structure_file="${output_dir}/STRUCTURE_${folder_name}_${current_datetime}.md"
flattened_file="${output_dir}/FLATTENED_${folder_name}_${current_datetime}.md"

# --- 2. USER CHOICES ---
# Ask the user to select the desired output type.
echo "Select output type:"
echo "  [1] Structure file only"
echo "  [2] Structure file AND Flattened content file (default)"
read -p "Enter your choice [1-2]: " output_choice
output_choice=${output_choice:-2} # Default to '2' if the user just presses Enter.

generate_flattened=false
if [[ "$output_choice" == "2" ]]; then
  generate_flattened=true
fi

# Initialize an array to hold all exclusion patterns.
all_excluded_patterns=()

# --- GITIGNORE EXCLUSION CHOICE ---
echo
read -p "Do you want to exclude all files and folders listed in .gitignore? ([1] Yes / [0] No, default: 1): " use_gitignore
use_gitignore=${use_gitignore:-1} # Default to '1' (Yes)

if [[ "$use_gitignore" == "1" ]]; then
    # --- NEW: Automatically add .git to the exclusion list ---
    # If the user opts into git-style exclusions, it's safe to assume
    # the .git directory itself should always be excluded.
    all_excluded_patterns+=(".git")

    gitignore_path="$folder_path/.gitignore"
    if [ -f "$gitignore_path" ]; then
        echo "Reading exclusions from $gitignore_path..."
        
        gitignore_patterns=()
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ ! "$line" =~ ^\s*# ]] && [[ -n "$(echo "$line" | tr -d '[:space:]')" ]]; then
                gitignore_patterns+=("$line")
            fi
        done < "$gitignore_path"
        
        all_excluded_patterns+=("${gitignore_patterns[@]}")
    else
        echo "Warning: .gitignore not found in the root of '$folder_path'. Continuing without it."
    fi
fi

# --- Ask for additional manual exclusions ---
echo
echo "You can now specify additional items to exclude from the output."
echo
read -p "Enter additional items to exclude (space-separated), or press Enter to skip: " -a manual_patterns

all_excluded_patterns+=("${manual_patterns[@]}")

# --- 3. PREPARE AND DISPLAY EXCLUSION ARGUMENTS ---

# Create a "cleaned" list of patterns.
cleaned_patterns=()
if [ ${#all_excluded_patterns[@]} -gt 0 ]; then
  for p in "${all_excluded_patterns[@]}"; do
      # Strip both leading AND trailing slashes for robust matching.
      temp_p="${p%/}"   # Remove trailing slash
      final_p="${temp_p#/}" # Remove leading slash
      cleaned_patterns+=("$final_p")
  done
fi

# --- Display Exclusions for User Confirmation ---
echo
if [ ${#cleaned_patterns[@]} -gt 0 ]; then
  echo "--- The following patterns will be excluded: ---"
  # Use sort -u to display a unique, alphabetized list for clarity
  printf "  - %s\n" $(echo "${cleaned_patterns[@]}" | tr ' ' '\n' | sort -u)
  echo "-----------------------------------------------"
else
  echo "--- No exclusion patterns are being used. ---"
fi
# ---

# Build exclude arguments for the `tree` command.
tree_exclude_args=()
if [ ${#cleaned_patterns[@]} -gt 0 ]; then
  # Create a unique list for the final arguments as well
  unique_patterns=($(echo "${cleaned_patterns[@]}" | tr ' ' '\n' | sort -u))
  joined_patterns=$(IFS="|"; echo "${unique_patterns[*]}")
  tree_exclude_args+=("-I" "$joined_patterns")
fi

# Build exclude arguments for the `find` command.
find_exclude_args=()
if [ ${#cleaned_patterns[@]} -gt 0 ]; then
    # Use the same unique list for find
    unique_patterns=($(echo "${cleaned_patterns[@]}" | tr ' ' '\n' | sort -u))
    find_exclude_args+=(-not "(")
    for pattern in "${unique_patterns[@]}"; do
        find_exclude_args+=(-path "*/$pattern/*" -o -path "*/$pattern" -o -name "$pattern" -o)
    done
    find_exclude_args=("${find_exclude_args[@]:0:${#find_exclude_args[@]}-1}")
    find_exclude_args+=(")")
fi

# --- 4. GENERATE STRUCTURE FILE ---
echo
echo "Generating directory structure..."

echo "# Directory Structure: $folder_name" > "$structure_file"
echo "**Generated:** $(date +'%Y-%m-%d %H:%M:%S')" >> "$structure_file"
echo -e "\n## Folder and File Tree\n" >> "$structure_file"

if command -v tree &>/dev/null; then
  echo '```' >> "$structure_file"
  (cd "$folder_path" && tree -a --noreport "${tree_exclude_args[@]}") >> "$structure_file"
  echo '```' >> "$structure_file"
else
  echo "Warning: 'tree' command not found. Using 'find' for a basic structure list."
  echo '```' >> "$structure_file"
  (cd "$folder_path" && find . "${find_exclude_args[@]}" | sort) >> "$structure_file"
  echo '```' >> "$structure_file"
fi

# --- 5. GENERATE FLATTENED CONTENT FILE (if requested) ---
if [ "$generate_flattened" = true ]; then
  echo "Generating flattened content file..."

  echo "# Flattened Content: $folder_name" > "$flattened_file"
  echo "**Generated:** $(date +'%Y-%m-%d %H:%M:%S')" >> "$flattened_file"
  
  files_to_process=()
  while IFS= read -r -d $'\0' file; do
      files_to_process+=("$file")
  done < <(find "$folder_path" "${find_exclude_args[@]}" -type f -print0)

  if [ ${#files_to_process[@]} -eq 0 ]; then
      echo "No files found to process after applying exclusions."
      echo -e "\n## File Contents\n\nNo text files found to include." >> "$flattened_file"
  else
      echo -e "\n## Summary\n" >> "$structure_file"
      echo "Total files included in flattened output: ${#files_to_process[@]}" >> "$structure_file"
      echo -e "\n## Included File Types\n" >> "$structure_file"
      echo '```' >> "$structure_file"
      for file in "${files_to_process[@]}"; do
        filename=$(basename "$file")
        extension="${filename##*.}"
        if [[ "$filename" == "$extension" ]]; then
            echo "(no extension)"
        else
            echo "$extension"
        fi
      done | sort | uniq -c | sort -rn >> "$structure_file"
      echo '```' >> "$structure_file"

      echo -e "\n## File Contents\n" >> "$flattened_file"
      
      for file in "${files_to_process[@]}"; do
        relative_path="${file#$folder_path/}"
        filename=$(basename "$file")
        extension="${filename##*.}"
        lang="text"
        display_content=1

        case "$extension" in
          js)   lang="javascript" ;; tsx)  lang="typescript" ;; ts)   lang="typescript" ;;
          json) lang="json" ;; md)   lang="markdown" ;; txt)  lang="text" ;;
          svg)  lang="xml" ;; html) lang="html" ;; css)  lang="css" ;;
          py)   lang="python" ;; java) lang="java" ;; rb)   lang="ruby" ;;
          sh|bash|zsh) lang="bash" ;; php)  lang="php" ;; c)    lang="c" ;;
          cpp)  lang="cpp" ;; h)    lang="c" ;; hpp)  lang="cpp" ;;
          go)   lang="go" ;; rs)   lang="rust" ;; sql)  lang="sql" ;;
          yaml|yml) lang="yaml" ;; xml)  lang="xml" ;;
          
          png|jpg|jpeg|gif|ico|webp|bmp|tiff)
            echo -e "\n### \`$relative_path\`\n\n**Binary image file (content not displayed)**" >> "$flattened_file"
            display_content=0 ;;
          
          pdf|doc|docx|xls|xlsx|ppt|pptx|zip|tar|gz|rar|bin|exe|dll|so|dylib|o|a|class|jar|war|ear|mp3|mp4|mov|avi)
            echo -e "\n### \`$relative_path\`\n\n**Binary file (content not displayed)**" >> "$flattened_file"
            display_content=0 ;;
          
          *)
            if ! file -bL --mime-encoding "$file" | grep -q 'us-ascii\|utf-8'; then
              echo -e "\n### \`$relative_path\`\n\n**Binary file detected (content not displayed)**" >> "$flattened_file"
              display_content=0
            fi ;;
        esac

        [ "$display_content" -eq 0 ] && continue

        echo -e "\n### \`$relative_path\`\n" >> "$flattened_file"
        echo '```'"${lang}" >> "$flattened_file"
        cat "$file" | LC_ALL=C sed 's/```/`` `/g' 2>/dev/null >> "$flattened_file"
        echo -e '\n```' >> "$flattened_file"
      done
  fi
fi

# --- 6. FINAL MESSAGES ---
echo
echo "---"
echo "✅ Success!"
echo "Directory structure written to: $structure_file"
if [ "$generate_flattened" = true ]; then
  echo "Flattened content written to: $flattened_file"
fi