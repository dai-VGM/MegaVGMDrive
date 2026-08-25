# Lab-build assignment guard. Abort if the inherited Golden Shell no longer
# maps MiSTer DDRAM through physical window 0x30000000.
set script_dir [file dirname [file normalize [info script]]]
set upload_file [file normalize [file join $script_dir .. .. rtl golden_player_shell golden_player_shell_upload.sv]]

if {![file isfile $upload_file]} {
    error "Metal Slug lab DDRAM audit: missing Golden Shell upload source: $upload_file"
}

set upload_fd [open $upload_file r]
set upload_text [read $upload_fd]
close $upload_fd

set base_pattern {\.DDRAM_BASE_ADDR[[:space:]]*\([[:space:]]*\{4'b0011,[[:space:]]*25'd0\}[[:space:]]*\)}
set pcm_pattern {\.SEGAPCM_ROM_BASE_ADDR[[:space:]]*\([[:space:]]*\{4'b0011,[[:space:]]*25'd0\}[[:space:]]*\+[[:space:]]*29'h0010_0000[[:space:]]*\)}

if {[regexp -all -- $base_pattern $upload_text] != 1} {
    error "Metal Slug lab DDRAM audit: normal DDRAM word base is missing or ambiguous"
}
if {[regexp -all -- $pcm_pattern $upload_text] != 1} {
    error "Metal Slug lab DDRAM audit: normal PCM DDRAM base is missing or ambiguous"
}

set ddram_word_base [expr {0x3 << 25}]
set ddram_physical_base [expr {$ddram_word_base << 3}]
if {$ddram_physical_base != 0x30000000} {
    error [format "Metal Slug lab DDRAM audit: physical base is 0x%08X" $ddram_physical_base]
}

puts "METAL_SLUG_REJECT_DDRAM_BASE_ASSERTION_PASS physical_base=0x30000000"
