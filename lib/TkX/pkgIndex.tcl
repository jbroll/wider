if {![package vsatisfies [package provide Tcl] 8.6]} {return}
package ifneeded TkX 1.0 [list ::apply {dir {
    source [file join $dir critcl-rt.tcl]
    set path [file join $dir [::critcl::runtime::MapPlatform]]
    set ext [info sharedlibextension]
    set lib [file join $path "TkX$ext"]
    load $lib Tkx
    package provide TkX 1.0
}} $dir]
