const { run } = require('./app');

exports.handle = async (event, context) => {
    context.callbackWaitsForEmptyEventLoop = true;
    await run();
}
