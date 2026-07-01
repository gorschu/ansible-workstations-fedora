# List available recipes
default:
    @just --list

repo_dir := justfile_directory()
hostname := `hostnamectl hostname`

[group('setup')]
phase1:
    "{{ repo_dir }}/run-playbook.sh" -l {{ hostname }} --tags phase1

[group('setup')]
phase2:
    "{{ repo_dir }}/run-playbook.sh" -l {{ hostname }} --tags phase2

[group('setup')]
phase3:
    "{{ repo_dir }}/run-playbook.sh" -l {{ hostname }} --tags phase3

[group('setup')]
phase4:
    "{{ repo_dir }}/run-playbook.sh" -l {{ hostname }} --tags phase4

[group('setup')]
setup *args:
    "{{ repo_dir }}/run-playbook.sh" -l {{ hostname }} {{ args }}

import? 'test.just'
