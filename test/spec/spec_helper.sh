# spec_helper.sh
# Add any common setup or helper functions here.

spec_helper_configure() {
  # Available functions: import, set, before_all, after_all, before_each, after_each
  set POSIX_MOCKS # Enable POSIX mocks for compatibility with /bin/sh in Docker
  # import <module_name> '<path>/<module_file>.sh' # Import modules
  :
}
