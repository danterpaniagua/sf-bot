// GITIN-2116 side finding (2026-10-05): proposed replacement for `Log.save` in api/src/utils/log.js (replaces lines 49 to the closing brace
// just before `saveError`, line 92 on origin/develop and origin/ope). NOT applied, NOT tested. Not part of the CVE changes.
//
// What it fixes:
//  - customDataAfter is a COPY (rest-destructuring), so message/level/category are no longer deleted from the caller's customData
//    (the alias on line 54 made `message: customData.message` undefined -> "Path message is required");
//  - a single Mongo write; if it fails, the failure is reported once on stdout and the function returns (no second/third create,
//    nothing thrown to the caller);
//  - the identical if/else branches are gone;
//  - a missing `message` gets a fixed placeholder instead of failing model validation.
    static async save(level = 'ERROR', error, customData = {}) {
        if (configs.consoleLogEnabled)
            Log._stdout(level, customData, error);
        if (!configs.mongoLogEnabled) return;
        try {
            const { message, level: _omitLevel, category, ...customDataAfter } = customData;
            await logErrorModel.create({
                message: message ?? '[INFRA/ERROR] log_without_message',
                level: VALID_LEVELS.includes(level) ? level : 'ERROR',
                category: VALID_CATEGORIES.includes(category) ? category : undefined,
                service: SERVICE_NAME,
                error: {
                    error: Log.serializeError(error) || 'Unknown error',
                    customDataAfter
                }
            });
        } catch (ex) {
            // Mongo logging must never break the caller nor retry against Mongo: report once on stdout and return.
            Log._stdout('FATAL', { message: '[INFRA/ERROR] Log.save failed', category: 'INFRA', original_message: customData?.message }, ex);
        }
    }
