/* ************************************************************************

   Copyrigtht: OETIKER+PARTNER AG
   License:    GPL
   Authors:    Tobias Oetiker
   $Id: MsgBox.js 1268 2010-12-02 10:20:07Z zaucker $
   Utf8Check:  äöü

************************************************************************ */

/**
 * @asset(qx/icon/${qx.icontheme}/32/status/dialog-error.png)
 * @asset(qx/icon/${qx.icontheme}/32/status/dialog-information.png)
 * @asset(qx/icon/${qx.icontheme}/32/status/dialog-warning.png)
 * @asset(qx/icon/${qx.icontheme}/16/status/dialog-warning.png)
 * @asset(qx/icon/${qx.icontheme}/16/status/dialog-error.png)
 * @asset(qx/icon/${qx.icontheme}/16/status/dialog-information.png)
 * @asset(qx/icon/${qx.icontheme}/16/actions/dialog-ok.png)
 * @asset(qx/icon/${qx.icontheme}/16/actions/dialog-apply.png)
 * @asset(qx/icon/${qx.icontheme}/16/actions/dialog-cancel.png)
 */

/**
 * A status window singleton. There is only one instance, several calls to
 * open will just change the windows content on the fly.
 *
 * <pre code='javascript'>
 * var msg = bwt.ui.MsgBox.getInstance();
 * msg.error('Title','Message');
 * </pre>
 */
qx.Class.define('agrammon.ui.dialog.MsgBox', {
    extend : qx.ui.window.Window,
    type : "singleton",

    construct : function() {
        this.base(arguments);

        this.set({
            modal          : true,
            showMinimize   : false,
            showMaximize   : false,
            resizable      : false,
            contentPadding : 15
        });

        this.setLayout(new qx.ui.layout.VBox(20));
//        var body = new qx.ui.basic.Atom();
        var body = new qx.ui.basic.Label();

        body.set({  // don't try to use wrap!
                     rich     : true,
                     wrap     : true,
//                     gap      : 10,
                     maxWidth : 500,
                     minWidth : 200
        });

        this.add(body);
        this.__body = body;

        var box = new qx.ui.container.Composite;
        box.setLayout(new qx.ui.layout.HBox(5, "right"));
        this.add(box);

        var that = this;

        var btn_cnl = this.__mk_btn(this.tr("Cancel"), "icon/16/actions/dialog-cancel.png");
        this.__btn_cnl = btn_cnl;

        btn_cnl.addListener("execute", function(e) {
            that.close();
        });

        box.add(btn_cnl);

        btn_cnl.addListener('appear', function(e) {
            btn_cnl.focus();
        }, this);

        var btn_app = this.__mk_btn(this.tr("Apply"), "icon/16/actions/dialog-apply.png");
        this.__btn_app = btn_app;

        btn_app.addListener("execute", function(e) {
            that.close();
        });

        box.add(btn_app);

        var btn_ok = this.__mk_btn(this.tr("OK"), "icon/16/actions/dialog-ok.png");
        this.__btn_ok = btn_ok;

        btn_ok.addListener("execute", function(e) {
            that.close();
        });

        btn_ok.addListener('appear', function(e) {
            btn_ok.focus();
        }, this);

        box.add(btn_ok);

        this.getApplicationRoot().add(this);
    },

    members : {
        __body : null,
        __btn_ok : null,
        __btn_app : null,
        __btn_cnl : null,


        /**
         * Open the message box
         *
         * @param titel {String} window title
         * @param text {String} contents
         * @return {void}
         */
        __open : function(titel, text) {
            this.setCaption(String(titel));
            this.__body.setValue(String(text));
            this.center();
            this.open();
        },


        /**
         * Create a button which is at least 40 pixel wide
         *
         * @param lab {String} label
         * @param ico {Icon} icon
         * @return {Button} button widget
         */
        __mk_btn : function(lab, ico) {
            var btn = new qx.ui.form.Button(lab, ico).set({ minWidth : 40 });
            return btn;
        },


        /**
         * Open the Error popup
         *
         * @param titel {String} title
         * @param text {String} body
         * @return {void}
         */
        error : function(titel, text) {
//            this.__body.setIcon("icon/32/status/dialog-error.png");
            this.setIcon("icon/16/status/dialog-error.png");
            this.__btn_ok.setVisibility('visible');
            this.__btn_app.setVisibility('excluded');
            this.__btn_cnl.setVisibility('excluded');
            this.__btn_ok.focus();
            this.__open(titel, text);
        },


        /**
         * Show server error message
         *
         * @param exc {Map} callAsync exception
         * @return {void}
         */
        exc : function(exc) {
//            this.__body.setIcon("icon/32/status/dialog-error.png");
            this.setIcon("icon/16/status/dialog-error.png");
            this.__btn_ok.setVisibility('visible');
            this.__btn_app.setVisibility('excluded');
            this.__btn_cnl.setVisibility('excluded');
            this.__btn_ok.focus();
            this.__open(this.tr('RPC Error %1', exc.code), this.tr('%1 (Error Code %2)', exc.message, exc.code));
        },

        /**
         * Show server error message
         *
         * @param msg {String} message to display
         * @param exc {Map} callAsync exception
         * @return {void}
         */
        exc2 : function(msg, exc) {
//            this.__body.setIcon("icon/32/status/dialog-error.png");
            this.setIcon("icon/16/status/dialog-error.png");
            this.__btn_ok.setVisibility('visible');
            this.__btn_app.setVisibility('excluded');
            this.__btn_cnl.setVisibility('excluded');
            this.__btn_ok.focus();
            this.__open(this.tr('RPC Error %1', exc.code), this.tr('%1 (Error Code %2)', msg+'<br/>'+exc.message, exc.code));
        },


        /**
         * Open the Info popup
         *
         * @param titel {String} title
         * @param text {String} body
         * @return {void}
         */
        info : function(titel, text) {
//            this.__body.setIcon("icon/32/status/dialog-information.png");
            this.setIcon("icon/16/status/dialog-information.png");
            this.__btn_ok.setVisibility('visible');
            this.__btn_app.setVisibility('excluded');
            this.__btn_cnl.setVisibility('excluded');
            this.__btn_ok.focus();
            this.__open(titel, text);
        },


        /**
         * Open a not yet implemented popup
         *
         * @param text {String} body
         * @return {void}
         */
        later : function(text) {
//            this.__body.setIcon("icon/32/status/dialog-information.png");
            this.setIcon("icon/16/status/dialog-information.png");
            this.__btn_ok.setVisibility('visible');
            this.__btn_app.setVisibility('excluded');
            this.__btn_cnl.setVisibility('excluded');
            this.__btn_ok.focus();
            this.__open(this.tr("Coming soon ..."), text);
        },


        /**
         * Open the Warning popup
         *
         * @param titel {String} title
         * @param text {String} body
         * @param exec_action {var} TODOC
         * @return {void}
         */
        warn : function(titel, text, exec_action) {
//            this.__body.setIcon("icon/32/status/dialog-warning.png");
            this.setIcon("icon/16/status/dialog-warning.png");
            this.__btn_ok.setVisibility('visible');
            this.__btn_cnl.setVisibility('excluded');
            this.__btn_app.setVisibility('excluded');
            this.__btn_ok.addListenerOnce("execute", exec_action);
            this.__open(titel, text);
        }
    }
});
