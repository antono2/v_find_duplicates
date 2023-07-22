module main

import os

// Eof error means that we reach the end of the file.
pub struct Eof {
	Error
}

[inline]
fn fread(ptr voidptr, item_size u32, item_count int, stream &C.FILE) !int {
	num_items := int(C.fread(ptr, item_size, item_count, stream))
	if num_items <= 0 {
		if C.feof(stream) != 0 {
			return Eof{}
		}
		if C.ferror(stream) != 0 {
			return error('file read error')
		}
	}
	return num_items
}

// Compares 2 files for each byte.
// Call like c_file_equal[u8](file1, file2, file_size) to compare the whole file bytewise. Type u8 is passed because V doesn't allow to initialized it like &u8{}.
// Agrument max_reads can be passed to only read a certain number of sizeof(T) bytes from the center.
// If max_reads is set, then the bytes from the first file are also returned to allow for caching.
fn c_file_equal[T](path1 string, path2 string, file_size u64, max_reads ...u64) bool {
	mut f1 := os.vfopen(path1, 'rb') or { return false }
	mut f2 := os.vfopen(path2, 'rb') or { return false }
	defer {
		C.fclose(f1)
		C.fclose(f2)
	}
	size_t := sizeof(T)
	b1, b2 := &T{}, &T{}
	mut eof1, mut eof2 := false, false
	mut read_count := u64(0)
	if max_reads.len > 0 {
		center_pos := u64(file_size / 2)
		// Put the file cursor in the center
		// SEEK_SET means from beginning of the file
		$if windows {
			C._fseeki64(f1, center_pos, C.SEEK_SET)
			C._fseeki64(f2, center_pos, C.SEEK_SET)
		} $else {
			C.fseeko(f1, center_pos, C.SEEK_SET)
			C.fseeko(f2, center_pos, C.SEEK_SET)
		}
	}
	for {
		if read_result := fread(b1, size_t, 1, f1) {
			if read_result != 1 {
				return false
			}
		} else {
			// End of file reached
			// Loop will be exited
			eof1 = true
		}
		if read_result := fread(b2, size_t, 1, f2) {
			if read_result != 1 {
				return false
			}
		} else {
			// End of file reached
			// Loop will be exited
			eof2 = true
		}
		if eof1 && eof2 {
			return true
		}
		if eof1 || eof2 {
			return false
		}
		if *b1 != *b2 {
			return false
		}
		read_count++
		if max_reads.len > 0 && read_count > max_reads[0] {
			return true
		}
	}
	return true
}
