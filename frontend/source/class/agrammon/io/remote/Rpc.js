/* ************************************************************************

   Copyrigtht: OETIKER+PARTNER AG
   License:    Proprietary
   Authors:    Tobias Oetiker, Fritz Zaucker

   $Id: Rpc.js 136 2010-06-15 21:57:02Z oetiker $

************************************************************************ */

/**
 * The Rpc class inherits from {@link qx.io.remote.Rpc}. It knows a bunch about
 * the way we like Rpc to happen in Agrammon context.
 *
 * Derived from Tobi's Nequal Rpc.js
 */
qx.Class.define('agrammon.io.remote.Rpc', {
    extend : qx.io.remote.Rpc,
    type : 'singleton',

    /**
     * Create an instance of Rpc.
     */
    construct : function() {
        this.base(arguments);

        this.set({
            timeout     : 25 * 1000,
            url         : 'jsonrpc/',
            serviceName : 'Agrammon'
        });
    },

    members : {

        __baseUrl:  '',
        __pending: null,

        // FIX ME: why is this needed anywhere?
        getBaseUrl : function() {
            return this.__baseUrl;
        },

        // Fix me: use Tobi's  asyncCall handler
        /**
         * A asyncCall handler which tries to
         * login in the case of a permission exception.
         *
         * @param handler {Function} the callback function.
         * @param methodName {String} the name of the method to call.
         * @param data {Map} the data to send.
         */
        callAsync : function(handler, methodName, data) {
            let req = new qx.io.request.Xhr(methodName, "POST");
            if (data != null) {
                req.setRequestData(data);
                req.setRequestHeader("Content-Type", "application/json");
            }
            if (methodName != 'auth' && methodName != 'get_cfg' && methodName != 'logout') {
                this.__pending = { methodName : methodName, data : data, handler : handler };
            }
            req.addListener("statusError", function(e) {
                let req = e.getTarget();
                this.handleStatusError(req, methodName, handler, data);
            }, this);
            let that = this;
            req.addListener("success", function(e) {
                let p = that.__pending;
                if (methodName == 'auth' && p) {
                    this.debug('retrying', p.methodName);
                    that.callAsync(p.handler, p.methodName, p.data);
                    p = null;
                }
                let response = e.getTarget().getResponse();
                try {
                    handler(response);
                }
                catch(e) {
                    if (window.console){
                        window.console.error("Error while running CallAsync Handler: response=", response, ", method=", methodName,", e=", e);
                    }
                }
            }, this);
            req.send();
        },

        handleStatusError : function(req, methodName, handler, data) {
            let response = req.getResponse();
            let status = req.getStatus();
            let statusText = req.getStatusText();
            // console.error('Rpc.callAsync('+methodName+'): status=', status, ':', statusText, ', response=', response, ', error=', response.error);
            let username = agrammon.Info.getInstance().getUserName();
            if (response && response.error) {
                let params = [
                    qx.locale.Manager.tr("Error") + ' ' + status,
                    response.error,
                    'error',
                ];
                if (!username) {
                    params.push( { msg: 'agrammon.main.logout', data: null} );
                }
                // no results
                if (methodName == 'get_output_variables') {
                    qx.event.message.Bus.dispatchByName('agrammon.Output.invalidate');
                }
                qx.event.message.Bus.dispatchByName('error', params);
                return;
            }
            else {
                let retry = true;
                let sudo  = null;
                let title = qx.locale.Manager.tr("Please authenticate yourself");
                switch (status) {
                case 404:
                case 401:
                    if (username) {
                        title = qx.locale.Manager.tr("%1: Session expired: please login again", status);
                    }
                    break;
                default:
                    title = qx.locale.Manager.tr("Error %1: %2 - please login again", status, statusText);
                    break;
                }
                new agrammon.module.user.Login(title, sudo, retry).open();
            }
            handler(data);
        },

        /* A variant of the asyncCall method which pops up error messages
         * generated by the server automatically.
         *
         * Note that the handler method only gets a return value never an exception
         * It just does not get called when there is an exception.
         *
         * @param handler {Function} the callback function.
         * @param methodName {String} the name of the method to call.
         * @return {var} the method call reference.
         */
        callAsyncSmart : function(handler, methodName) {
            let origHandler = handler;

            let superHandler = function(ret, exc, id) {
                if (exc) {
                    agrammon.ui.dialog.MsgBox.getInstance().exc(exc);
                } else {
                    origHandler(ret);
                }
            };
            arguments[0] = superHandler;
            this.callAsync.apply(this, arguments);
        }
    }
});
