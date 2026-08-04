-- Adds an optional icon to categories (issue #14: "Add icons to the
-- categories"). Nullable with no default so existing rows just fall back to
-- the app's default icon (see lib/utils/category_icons.dart) until edited.
alter table categories add column icon text;
