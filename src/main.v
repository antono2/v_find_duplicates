/*##################################################
###                                              ###
### Fast file duplicate finder                   ###
###                                              ###
### Author antono2@github                        ###
###                                              ###
### License MIT                                  ###
###                                              ###
### https://github.com/antono2/v_find_duplicates ###
###                                              ###
##################################################*/
module main


import os
import json


pub struct Duplicates {
mut:
	size_bytes u64
	paths      []string
}

pub struct DirectoryInfo {
mut:
	size_bytes   u64
	files_in_dir []string
}

// Checks if the same size file is actually the same bytewise.
// Returns an array of Duplicates ordered by size descending.
fn find_duplicates(size_map &map[u64][]string, num_bytes_to_compare u64) []Duplicates {
	mut ret := map[u64][]string{}
	for key, itm in size_map {
		// All paths in itm have the same file size
		if itm.len > 1 {
			for i in 1 .. itm.len {
				// File i has same bytes as file 0
				// First file 0 is the reference for all others
				if c_file_equal[u8]((*itm)[0], (*itm)[i], key, num_bytes_to_compare) {
					if key in ret {
						ret[key] << (*itm)[i]
					} else {
						ret[key] << (*itm)[0]
						ret[key] << (*itm)[i]
					}
				}
			}
		}
	}
	mut ret_arr := []Duplicates{}
	mut ret_keys_sorted := ret.keys()
	ret_keys_sorted.sort(a > b)
	for _, key in ret_keys_sorted {
		ret_arr << Duplicates{
			size_bytes: key
			paths: ret[key]
		}
	}
	return ret_arr
}

fn os_dir_with_slash_for_dot(path string) string {
	mut ret := os.dir(path)
	if ret == "." { return "./" }
	return ret
}

// Looks for directories in list of duplicates, which have exactly the same content.
// Returns an array of duplicates containing the directory size and its duplicates.
fn find_duplicate_directories(duplicates []Duplicates) []Duplicates {
	mut ret := map[u64][]string{}
	if duplicates.len == 0 {
		return []Duplicates{}
	}

	// Map all directories containing duplicate files
	// and walk through each - stopping on a difference.
	mut dirs := map[string]DirectoryInfo{}
	for _, itm in duplicates {
		for path in itm.paths {
			cur_dir := os_dir_with_slash_for_dot(path)
			if cur_dir !in dirs {
				dirs[cur_dir] = DirectoryInfo{}
			}
			if cur_dir in dirs { continue }
		}
	}

	// TODO: Optimize to walk multiple dirs in parallel and stop on difference
	// TODO: Don't walk the same dirs multiple times.
	//	 Maybe store walked to end paths
	for key, mut dir_info in dirs {
		// Again, need to pass a pointer or cur_size will be passed by value in os.walk.
		// use &cur_size in os.walk won't work
		mut cur_size := &[u64(0)]
		os.walk(key, fn [mut dir_info, mut cur_size] (f string) {
			if !os.exists(f) {
				return
			}
			// TODO: Maybe call file_size later, but need to iterate all over again
			file_size := os.file_size(f)
			if file_size != 0 { 
				// cur_size + file_size doesn't work
				//mut omg_new_temporary_size_cause_of__why_exactly := (*cur_size) + file_size
				cur_size[0] += file_size							
				//cur_size = &omg_new_temporary_size_cause_of__why_exactly
			}
			dir_info.files_in_dir << f
		})
		dir_info.size_bytes = cur_size[0]
	}
	if dirs.keys().len <= 1 { return []Duplicates{} } 
	// Build ret
	for _, _ in dirs {
		for duplicate in duplicates {
			// Again, only the first directory is compared to all others
			for i in 0 .. duplicate.paths.len {
				first_file_dir := os_dir_with_slash_for_dot(duplicate.paths[0])
				cur_file_dir := os_dir_with_slash_for_dot(duplicate.paths[i])
				if dirs[first_file_dir].files_in_dir.len == dirs[cur_file_dir].files_in_dir.len
					&& dirs[first_file_dir].size_bytes == dirs[cur_file_dir].size_bytes {
					tmp_size := dirs[first_file_dir].size_bytes
					if tmp_size in ret {
						ret[tmp_size] << cur_file_dir
					} else {
						ret[tmp_size] << first_file_dir
						ret[tmp_size] << cur_file_dir
					}
				}
			}
		}
	}
	mut ret_arr := []Duplicates{}
	mut ret_keys_sorted := ret.keys()
	ret_keys_sorted.sort(a > b)
	for _, key in ret_keys_sorted {
		ret_arr << Duplicates{
			size_bytes: key 
			paths: ret[key]
		}
	}
	return ret_arr
}

fn main() {
	min_file_size_bytes := u64(1024 * 10) // 10kb
	num_bytes_to_compare := u64(1024) // compared from center of file
	out_file := './duplicate_files.json'
	out_file_dirs := './duplicate_directories.json'

	mut working_dirs := []string{}
	if os.args.len > 1 {
		for i in 1 .. os.args.len {
			working_dirs << os.args[i]
		}
	} else {
		working_dirs << './'
	}
	// Has to be reference, otherwise it's passed by value to os.walk
	mut size_map := &map[u64][]string{}
	for _, cwd in working_dirs {
		println('Scanning directory for duplicates: ${cwd}')
		// map of file size to array of file path
		os.walk(cwd, fn [mut size_map, min_file_size_bytes] (f string) {
			if !os.exists(f) {
				return
			}
			fsize := os.file_size(f)
			if fsize != 0 {
				if fsize < min_file_size_bytes {
					return
				}
				size_map[fsize] << f
			}
		})
	}
	duplicates := find_duplicates(size_map, num_bytes_to_compare)
	//println('Duplicate Files: ${duplicates}')
	os.write_file(out_file, json.encode(duplicates))!
	duplicate_directories := find_duplicate_directories(duplicates)
	println('Duplicate Directories: ${duplicate_directories}')
	os.write_file(out_file_dirs, json.encode(duplicate_directories))!
}
