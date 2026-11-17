'use strict';
module.exports={spawn(){const error=new Error('Native shell/PTY subprocesses are not supported inside the iOS application sandbox.');error.code='ERR_IOS_PTY_UNSUPPORTED';throw error;}};