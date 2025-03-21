/* ************************************************************************

************************************************************************ */

qx.Class.define('agrammon.Application', {
    extend: qx.application.Standalone,

    members: {

        /**
          * TODOC
          *
          * @return {var} TODOC
              * @lint ignoreDeprecated(alert)
          */
        main: function() {
            this.base(arguments);

            let rv = -1; // Return value assumes failure.
            if (navigator.appName == 'Microsoft Internet Explorer') {
                let ua = navigator.userAgent;
                let re  = new RegExp("MSIE ([0-9]{1,}[\.0-9]{0,})");
                if (re.exec(ua) != null) {
                    rv = parseFloat( RegExp.$1 );
                }
            }
            if (rv>0 && rv<7) {
                alert(this.tr("Agrammon is not supported on Internet Explorer below version 7"));
                this.terminate();
            }

            // Enable logging in debug variant
            if ((qx.core.Environment.get("qx.debug"))) {
                // support native logging capabilities, e.g. Firebug for Firefox
                qx.log.appender.Native;
                // support additional cross-browser console. Press F7 to toggle visibility
                qx.log.appender.Console;
            }

            let param, params = this.__getParams();
            for (let i=0; i<params.length; i++) {
                if (params[i] != null) {
                    param = params[i].split("=");
                }
                if (param[0] == 'lang') {
                    qx.locale.Manager.getInstance().setLocale(param[1]);
                }
            }

            let that = this;

            this.__rpc = agrammon.io.remote.Rpc.getInstance();

            qx.event.message.Bus.subscribe('agrammon.main.logout', this.__logout, this);
            qx.event.message.Bus.subscribe('agrammon.main.login',  this.__login,  this);

            let root = this.getRoot();
            root.setBlockerColor("#bfbfbf");
            root.setBlockerOpacity(0.5);

            // Add a popup error/info window to the application it will display
            // messages sent to the error message bus.
            root.add(new agrammon.ui.dialog.Error());

            // Dto for help messages.
            root.add(new agrammon.ui.dialog.Help());

            // Dto for log messages.
            root.add(new agrammon.ui.dialog.Log());

            let loginDialog =
                new agrammon.module.user.Login(this.tr("Please authenticate yourself"));
            this.__loginDialog = loginDialog;

            for (let id in qx.core.Id.getInstance().getRegisteredObjects()) {
                this.debug('Id=', id);
            }

            for (let o of loginDialog.getOwnedQxObjects()) {
                this.debug('Id=', qx.core.Id.getAbsoluteIdOf(o));
            }

            // the base layout of the page.
            let main = new qx.ui.container.Composite(new qx.ui.layout.VBox());
            main.set({ padding: 5 });

            root.add(main, { edge: 0 });

            let title = new qx.ui.basic.Label().set({
                value          : 'AGRAMMON', // will be overwritten from config
                font           : qx.bom.Font.fromString('14px bold sans-serif'),
                textColor      : '#808080'
            });

            let output     = new agrammon.module.output.Output(false);
            let reference  = new agrammon.module.output.Output(true);

            let propEditor = new agrammon.module.input.PropTable('InputTable');
            let navbar     = new agrammon.module.input.NavBar(propEditor);

            let mainMenu;

            let results;
            let getCfgFunc = qx.lang.Function.bind(function(data, exc, id) {
                if (exc == null) {
                    this.debug('getCfgFunc(): title='   +data.title.en);
                    this.debug('getCfgFunc(): version=' +data.version);
                    this.debug('getCfgFunc(): variant=' +data.variant);
                    this.debug('getCfgFunc(): guiVariant=' +data.guiVariant);
                    this.debug('getCfgFunc(): modelVariant=' +data.modelVariant);

                    if (data.guiVariant != 'Regional') {
                        results = new agrammon.module.output.Results(output);
                    }
                    let input      = new agrammon.module.input.Input(propEditor, navbar, results);
                    let tabview    = new agrammon.module.Main(input, output, reference);
                    let editMenu   = new agrammon.ui.menu.NavMenu(navbar);
                    mainMenu       = new agrammon.ui.menu.MainMenu(tabview, title, editMenu);

                    main.add(mainMenu);
                    main.add(tabview, { flex : 1 });
                    main.add(new agrammon.Footer(this.tr("Implemented by OETIKER+PARTNER AG. Copyright 2010-"), 'http://www.oetiker.ch/'));

                    navbar.setVariant(data.modelVariant);
                    agrammon.module.dataset.DatasetTable.getInstance().setVariant(data.variant);
                    mainMenu.setTitle(data.title, data.version);
                    let info = agrammon.Info.getInstance();
                    info.setVersion(data.version);
                    info.setVariant(data.variant);
                    info.setGuiVariant(data.guiVariant);
                    info.setModelVariant(data.modelVariant);
                    info.setTitle(data.title);
                    info.setSubmissionAddresses(data.submission);
                            qx.event.message.Bus.dispatchByName('agrammon.Info.setModelVariant', data.modelVariant);
                }
                else {
                    alert(exc);
                }
                loginDialog.open();
            }, this);

            this.__rpc.callAsync( getCfgFunc, 'get_cfg');

            this.__authenticate = function(data, exc, id) {
                // console.log('Application.__authenticate():', data, exc, id);
                if (exc == null) {
                    let username  = data.username;
                    let role      = data.role;
                    let news      = data.news;
                    let lastLogin = String(data.lastLogin);
                    qx.event.message.Bus.dispatchByName(
                        'agrammon.info.setUser',
                        { username : username, role : role }
                    );
                    if (!that.__retry) {
                        if (news && news != '') {
                            var dialog = new agrammon.ui.dialog.News(
                                that.tr("Latest news"),
                                news,
                                function () {
                                    dialog.close();
                                    qx.event.message.Bus.dispatchByName('agrammon.FileMenu.openConnect');
                                },
                                lastLogin
                            );
                        }
                        else {
                            qx.event.message.Bus.dispatchByName('agrammon.FileMenu.openConnect');
                        }
                    }
                    // enable admin menu
                    mainMenu.showAdmin(role == 'admin' || role == 'support');
                    propEditor.setRole(role);
//                    if (results && role != 'admin') { // TODO: fix update
//                        results.exclude();
//                    }
                    qx.event.message.Bus.dispatchByName('agrammon.DatasetCache.refresh', username);
                }
                else {
                    qx.event.message.Bus.dispatchByName('error',
                         [ qx.locale.Manager.tr("Authentication error"),
                           qx.locale.Manager.tr("Invalid username or password"),
                           'error',
                           { msg: 'agrammon.main.logout', data: null}
                         ]
                    );
                }
            };

        },

 /********************************************************************
 * Functional Block Methods
 ********************************************************************/

        __authenticate: null,
        __retry:        null,
        __rpc:          null,
        __loginDialog:  null,

        close : function(e) {
            this.base(arguments);
            console.log('Application.close()');
            // Prompt user
            // return "AGRAMMON: Do you really want to close the application?";
        },

        terminate : function(e) {
            this.base(arguments);
            console.log('Application.terminate()');
        },

        __getParams : function() {
            let params = "";
            let urlParams = window.location.search;
            if (urlParams.length > 0) {
                urlParams = urlParams.substr(1, urlParams.length);
                if (params != null) {
                    params = urlParams.split("&");
                }
            }
            return params;
        },

        __login: function(msg) {
            let userData     = msg.getData();
            this.__retry = userData.retry;
            this.debug('__login(' + userData.username + ')');
            if (userData.sudoUsername === undefined) {
                userData.sudoUsername = null;
            }
            this.__rpc.callAsync(this.__authenticate, 'auth', userData);
        },

        __logout: function() {
            // console.log('Application.__logout()');
            this.__rpc.callAsync( qx.lang.Function.bind(this.__logoutFunc,this), 'logout');
            qx.event.message.Bus.dispatchByName('agrammon.NavBar.clearTree', null);
            qx.event.message.Bus.dispatchByName('agrammon.input.select');
        },

        __logoutFunc: function(data, exc, id) {
            // console.log('Application.__logoutFunc():', data, exc, id);
            if (exc == null || exc == 403) {
                if (data && data.sudoUser) {
                    let infoOnly = true;
                    let dialog = new agrammon.ui.dialog.Confirm(
                        this.tr("End change user"),
                        this.tr("Returning from %1 to %2", data.sudoUser, data.username),
                        qx.lang.Function.bind(function() {
                            this.__authenticate(data, exc, id);
                            dialog.close()
                        }, this),
                        this,
                        infoOnly
                    );
                    return;
                }
                qx.event.message.Bus.dispatchByName('agrammon.info.setUser',    '-');
                qx.event.message.Bus.dispatchByName('agrammon.info.setDataset', '-');
            }
            else {
                alert(exc);
            }
            this.__loginDialog.open();
        }
    }
});
