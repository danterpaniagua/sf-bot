const crypto = require('crypto');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const secretsClient = new SecretsManagerClient({});
let cachedSecret;

function base64UrlDecode(str) {
  str = str.replace(/-/g, '+').replace(/_/g, '/');
  while (str.length % 4) str += '=';
  return Buffer.from(str, 'base64');
}

function verifyJwtHS256(token, secret) {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Malformed token');
  const [headerB64, payloadB64, sigB64] = parts;
  const expectedSig = crypto.createHmac('sha256', secret).update(`${headerB64}.${payloadB64}`).digest();
  const actualSig = base64UrlDecode(sigB64);
  if (expectedSig.length !== actualSig.length || !crypto.timingSafeEqual(expectedSig, actualSig)) {
    throw new Error('Invalid signature');
  }
  const payload = JSON.parse(base64UrlDecode(payloadB64).toString('utf8'));
  if (payload.exp && Date.now() / 1000 > payload.exp) throw new Error('Token expired');
  return payload;
}

function generatePolicy(principalId, effect, resource) {
  return {
    principalId,
    policyDocument: {
      Version: '2012-10-17',
      Statement: [{
        Action: 'execute-api:Invoke',
        Effect: effect,
        Resource: resource,
      }],
    },
  };
}

exports.handler = async (event) => {
  const token = (event.authorizationToken || '').replace(/^Bearer\s+/i, '');
  if (!token) throw new Error('Unauthorized');

  if (!cachedSecret) {
    const resp = await secretsClient.send(
      new GetSecretValueCommand({ SecretId: 'poc-arq009/jwt-secret' })
    );
    cachedSecret = resp.SecretString;
  }

  let payload;
  try {
    payload = verifyJwtHS256(token, cachedSecret);
  } catch (err) {
    throw new Error('Unauthorized');
  }

  const branchIdFromToken = payload && payload.user && payload.user.branchId;

  // methodArn shape: arn:aws:execute-api:{region}:{account}:{apiId}/{stage}/{METHOD}/{branchId}
  const methodArnParts = event.methodArn.split('/');
  const branchIdFromPath = methodArnParts[methodArnParts.length - 1];

  if (!branchIdFromToken || branchIdFromToken !== branchIdFromPath) {
    return generatePolicy(branchIdFromToken || 'unknown', 'Deny', event.methodArn);
  }

  // Allow both GET and POST for this branchId path — same token, same branch, either verb.
  const arnPrefix = methodArnParts.slice(0, methodArnParts.length - 2).join('/');
  const wildcardResource = `${arnPrefix}/*/${branchIdFromPath}`;

  return generatePolicy(branchIdFromToken, 'Allow', wildcardResource);
};
