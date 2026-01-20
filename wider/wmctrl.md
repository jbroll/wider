he API is now:

  wm::windows                              # list all windows
  wm::state $id add|remove|toggle prop...  # state changes
  wm::move $id ?desktop? x y ?w h?         # move/resize
  wm::xprop $id                            # list all properties
  wm::xprop $id prop                       # get property
  wm::xprop $id prop value                 # set property
