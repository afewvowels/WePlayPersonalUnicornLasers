data:extend({
  {
    type = "int-setting",
    name = "wp-pul-scale",
    setting_type = "runtime-global",
    default_value = 1,
    allowed_values = {1, 2, 3, 4, 5},
    order = "a",
  },
  {
    type = "int-setting",
    name = "wp-pul-speed",
    setting_type = "runtime-global",
    default_value = 1,
    allowed_values = {1, 2, 3, 4},
    order = "b",
  },
  {
    type = "double-setting",
    name = "wp-pul-saturation",
    setting_type = "runtime-global",
    default_value = 0.85,
    minimum_value = 0,
    maximum_value = 1,
    order = "c",
  },
})
