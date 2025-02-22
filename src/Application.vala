using Gtk;

namespace Tooth {

	public errordomain Oopsie {
		USER,
		PARSING,
		INSTANCE,
		INTERNAL
	}

	public static Application app;

	public static Settings settings;
	public static AccountStore accounts;
	public static Network network;
	public static Streams streams;

	public static EntityCache entity_cache;
	public static ImageCache image_cache;

	public static GLib.Regex custom_emoji_regex;
	public static GLib.Regex rtl_regex;
	public static bool is_rtl;

	public static bool start_hidden = false;

	public class Application : Adw.Application {

		public Dialogs.MainWindow? main_window { get; set; }
		public Dialogs.NewAccount? add_account_window { get; set; }

		// These are used for the GTK Inspector
		public Settings app_settings { get {return Tooth.settings; } }
		public AccountStore app_accounts { get {return Tooth.accounts; } }
		public Network app_network { get {return Tooth.network; } }
		public Streams app_streams { get {return Tooth.streams; } }

		public signal void refresh ();
		public signal void toast (string title);

		public CssProvider css_provider = new CssProvider ();
		public CssProvider zoom_css_provider = new CssProvider (); //FIXME: Zoom not working

		public const GLib.OptionEntry[] app_options = {
			{ "hidden", 0, 0, OptionArg.NONE, ref start_hidden, "Do not show main window on start", null },
			{ null }
		};

		private const GLib.ActionEntry[] app_entries = {
			{ "about", about_activated },
			{ "compose", compose_activated },
			{ "back", back_activated },
			{ "refresh", refresh_activated },
			{ "search", search_activated },
		};

		construct {
			application_id = Build.DOMAIN;
			flags = ApplicationFlags.HANDLES_OPEN;
		}

		public string[] ACCEL_ABOUT = {"F1"};
		public string[] ACCEL_NEW_POST = {"<Ctrl>T"};
		public string[] ACCEL_BACK = {"<Alt>BackSpace", "<Alt>Left"};
		public string[] ACCEL_REFRESH = {"<Ctrl>R", "F5"};
		public string[] ACCEL_SEARCH = {"<Ctrl>F"};

		public static int main (string[] args) {
			try {
				var opt_context = new OptionContext ("- Options");
				opt_context.add_main_entries (app_options, null);
				opt_context.parse (ref args);
			}
			catch (GLib.OptionError e) {
				warning (e.message);
			}

			try {
				custom_emoji_regex = new GLib.Regex("(:[a-zA-Z0-9_]{2,}:)", GLib.RegexCompileFlags.OPTIMIZE);
			} catch (GLib.RegexError e) {
				warning (e.message);
			}

			try {
				rtl_regex = new GLib.Regex("[\u0591-\u07FF\uFB1D-\uFDFD\uFE70-\uFEFC]", GLib.RegexCompileFlags.OPTIMIZE, GLib.RegexMatchFlags.ANCHORED);
			} catch (GLib.RegexError e) {
				warning (e.message);
			}

			app = new Application ();
			return app.run (args);
		}

		protected override void startup () {
			base.startup ();
			try {
				Build.print_info ();
				Adw.init ();

				settings = new Settings ();
				streams = new Streams ();
				network = new Network ();
				entity_cache = new EntityCache ();
				image_cache = new ImageCache ();
				accounts = new SecretAccountStore();
				accounts.init ();

				//  css_provider.load_from_resource (@"$(Build.RESOURCES)app.css");
				StyleContext.add_provider_for_display (Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
				StyleContext.add_provider_for_display (Gdk.Display.get_default (), zoom_css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
			}
			catch (Error e) {
				var msg = _("Could not start application: %s").printf (e.message);
				inform (Gtk.MessageType.ERROR, _("Error"), msg);
				error (msg);
			}

			var style_manager = Adw.StyleManager.get_default ();
			ColorScheme color_scheme = (ColorScheme) settings.get_enum ("color-scheme");
			style_manager.color_scheme = color_scheme.to_adwaita_scheme ();

			set_accels_for_action ("app.about", ACCEL_ABOUT);
			set_accels_for_action ("app.compose", ACCEL_NEW_POST);
			set_accels_for_action ("app.back", ACCEL_BACK);
			set_accels_for_action ("app.refresh", ACCEL_REFRESH);
			set_accels_for_action ("app.search", ACCEL_SEARCH);
			add_action_entries (app_entries, this);
		}

		protected override void activate () {
			present_window ();

			if (start_hidden) {
				start_hidden = false;
				return;
			}
			settings.delay ();
		}

		protected override void shutdown () {
			settings.apply ();
			base.shutdown ();
		}

		public override void open (File[] files, string hint) {
			foreach (File file in files) {
				string uri = file.get_uri ();
				if (add_account_window != null)
					add_account_window.redirect (uri);
				else
					warning (@"Received an unexpected uri to open: $uri");
				return;
			}
		}

		public void present_window (bool destroy_main = false) {
			if (accounts.saved.is_empty) {
				if (main_window != null && destroy_main)
					main_window.hide();
				message ("Presenting NewAccount dialog");
				if (add_account_window == null)
					new Dialogs.NewAccount ();
				add_account_window.present ();
			}
			else {
				message ("Presenting MainWindow");
				if (main_window == null) {
					main_window = new Dialogs.MainWindow (this);
					is_rtl = Gtk.Widget.get_default_direction() == Gtk.TextDirection.RTL;
				}
				main_window.present ();
			}
			main_window.close_request.connect(on_window_closed);
		}

		public bool on_window_closed () {
			if (!settings.work_in_background || accounts.saved.is_empty) {
				main_window.hide_on_close = false;
			} else {
				main_window.hide_on_close = true;
			}

			return false;
		}

		void compose_activated () {
			new Dialogs.Compose ();
		}

		void back_activated () {
			main_window.back ();
		}

		void search_activated () {
			main_window.open_view (new Views.Search ());
		}

		void refresh_activated () {
			refresh ();
		}

		void about_activated () {
			const string[] artists = {
				"Tobias Bernard"
			};

			const string[] developers = {
				"bleak_grey",
				"Evangelos \"GeopJr\" Paterakis"
			};

			var dialog = new Adw.AboutWindow () {
				transient_for = main_window,
				modal = true,

				application_icon = Build.DOMAIN,
				application_name = Build.NAME,
				version = Build.VERSION,
				support_url = Build.SUPPORT_WEBSITE,
				license_type = License.GPL_3_0_ONLY,
				copyright = Build.COPYRIGHT,
				debug_info = Build.SYSTEM_INFO,
				developers = developers,
				artists = artists,
				translator_credits = Build.TRANSLATOR != " " ? Build.TRANSLATOR : ""
			};

			// For some obscure reason, const arrays produce duplicates in the credits.
			// Static functions seem to avoid this peculiar behavior.
			//  dialog.translator_credits = Build.TRANSLATOR != " " ? Build.TRANSLATOR : null;

			dialog.present ();
		}

		public void inform (Gtk.MessageType type, string text, string? msg = null, Gtk.Window? win = main_window){
			var dlg = new Gtk.MessageDialog (
				win,
				Gtk.DialogFlags.MODAL,
				type,
				Gtk.ButtonsType.OK,
				null
			);
			dlg.text = text;
			dlg.secondary_text = msg;
			dlg.transient_for = win;
			// dlg.run ();
			dlg.destroy ();
		}

		public Adw.MessageDialog question (string text, string? msg = null, Gtk.Window? win = main_window, string yes_label = _("Yes"), Adw.ResponseAppearance yes_appearence = Adw.ResponseAppearance.DEFAULT, string no_label = _("Cancel"), Adw.ResponseAppearance no_appearence = Adw.ResponseAppearance.DEFAULT) {
			var dlg = new Adw.MessageDialog (
				win,
				text,
				msg
			);

			dlg.add_response("no", no_label);
			dlg.set_response_appearance("no", no_appearence);

			dlg.add_response("yes", yes_label);
			dlg.set_response_appearance("yes", yes_appearence);

			dlg.transient_for = win;
			return dlg;
		}

	}

}
