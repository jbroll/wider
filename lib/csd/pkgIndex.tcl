if {![package vsatisfies [package provide Tcl] 8.6]} {return}
package ifneeded csd 0.2 [list ::apply {dir {
    source [file join $dir critcl-rt.tcl]
    set path [file join $dir [::critcl::runtime::MapPlatform]]
    set ext [info sharedlibextension]
    set lib [file join $path "csd$ext"]
    load $lib Csd
    package provide csd 0.2
}} $dir]
