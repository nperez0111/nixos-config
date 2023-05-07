let
  macminiuser =
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDz0bAXfQclIXShHgYYsPS2Xzzkq0/7Am47M2APWzVqOnX7rIqSbcqdQ0g1E0zF5fWsHjJlQLCrHGAoKa+YXQL8pmRnsa7wdx//s+8MrrMQg744qokYPwP6cIhK0edYUgUIGLCPyducsrGA4Vjexn6+tx5SygP3gDfO+lp2BLxZaTQEpkfKeysp5iU3BybQB1EhXmdjVNhxdAun7YTYjbzVp1KNcXraSdDEt75x/SkcRVJEHTExjiPo23Q62aS5H9r1TX6Se0pZvcTURv8trBesxVX5WqmxpKCCc82m/cHbvyZIwmEXEQGuljXiXwpZ1+HOHIcg5XtP0LBjtc1mlNTkRADUT6oZ1P8ycXOTfXL+zwwYNQmJrztWYzU8xt2xQRPjGZTavoR7Qe6vDGOkHnzb8ghnFVZo6itwNz6mxCdhv6fi8wvsGBh+seFmxsxh5i2GOuVWFoOymLK7JAur3vo5QnTu9rv3TsiSM2FTnX6s1GlF9I3VwweMdkNTy0PnwgU= nickthesick@nickthesicks-Mac-mini.local";
  users = [ macminiuser ];

  macmini =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdaJHsDBwdj8kq+2fQ51cPuWsXgqZHi5xvNIRZ0lOVr";
  systems = [ macmini ];
in {
  "github".publicKeys = users ++ systems;
  "ssh_pub".publicKeys = users ++ systems;
}
