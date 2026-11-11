#!/bin/sh
set -eu

rel=${1:?usage: $0 <gnome release, e.g. 49> [outdir]}
out=${2:-packages}
base=https://download.gnome.org/sources

pkgs="gsettings-desktop-schemas mutter gnome-settings-daemon gnome-session
gnome-shell xdg-desktop-portal-gnome gnome-control-center nautilus"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

deps_of() {
	case $1 in
		gsettings-desktop-schemas) echo "glib" ;;
		mutter) echo "glib gsettings-desktop-schemas elogind" ;;
		gnome-settings-daemon) echo "glib gsettings-desktop-schemas elogind" ;;
		gnome-session) echo "glib gnome-settings-daemon" ;;
		gnome-shell) echo "mutter gnome-session gnome-settings-daemon" ;;
		xdg-desktop-portal-gnome) echo "gsettings-desktop-schemas" ;;
		gnome-control-center) echo "gnome-settings-daemon" ;;
		nautilus) echo "gsettings-desktop-schemas" ;;
	esac
}

for n in $pkgs; do
	f=$(curl -fsL "$base/$n/$rel/" | grep -o "$n-[0-9][0-9.]*\.tar\.xz" | sort -uV | tail -1)
	[ -n "$f" ] || { echo "$n: nothing for $rel" >&2; exit 1; }

	v=${f#"$n"-}
	v=${v%.tar.xz}
	dir=${f%.tar.xz}

	curl -fsLo "$tmp/$f" "$base/$n/$rel/$f"
	sum=$(sha256sum "$tmp/$f" | cut -d' ' -f1)
	opts=$(tar -xOf "$tmp/$f" "$dir/meson.options" "$dir/meson_options.txt" 2>/dev/null || true)

	has() { printf '%s\n' "$opts" | grep -q "option('$1'"; }

	flags=
	if has systemd; then flags="$flags -Dsystemd=false"; fi
	if has systemd_session; then flags="$flags -Dsystemd_session=disable"; fi
	if has systemd_journal; then flags="$flags -Dsystemd_journal=false"; fi
	if [ "$n" = nautilus ]; then
		flags="$flags -Dtests=none"
	elif has tests; then
		flags="$flags -Dtests=false"
	fi

	mkdir -p "$out/$n"
	{
		printf 'return {\n'
		printf '\tname = "%s",\n' "$n"
		printf '\tversion = "%s",\n' "$v"
		printf '\turl = "%s/%s/%s/%s",\n' "$base" "$n" "$rel" "$f"
		printf '\tsha256 = "%s",\n' "$sum"
		ds=$(deps_of "$n")
		if [ -n "$ds" ]; then
			printf '\tdeps = {'
			for dep in $ds; do printf ' "%s",' "$dep"; done
			printf ' },\n'
		fi
		printf '\tarchive = { strip = 1 },\n'
		printf '\tbuild = function(p)\n'
		printf '\t\tp:run("meson setup build --prefix " .. p.prefix .. " --buildtype=release%s")\n' "$flags"
		printf '\t\tp:env_set("DESTDIR", p.install_root)\n'
		printf '\t\tp:ninja("-C", "build")\n'
		printf '\t\tp:ninja("-C", "build", "install")\n'
		printf '\tend,\n'
		printf '}\n'
	} > "$out/$n/package.lua"
done
