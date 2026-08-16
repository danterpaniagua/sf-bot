const crypto = require('crypto');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const { SQSClient, SendMessageCommand, ReceiveMessageCommand } = require('@aws-sdk/client-sqs');

const REGION = 'us-west-2';
const ACCOUNT_ID = '382381053403';
const QUEUE_PREFIX = 'poc-arq009';

const secretsClient = new SecretsManagerClient({});
const sqsClient = new SQSClient({});
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

function response(statusCode, bodyObj) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(bodyObj),
  };
}

exports.handler = async (event) => {
  const branchIdFromPath = event.pathParameters && event.pathParameters.branchId;
  const method = event.requestContext.http.method;
  const authHeader = (event.headers && (event.headers.authorization || event.headers.Authorization)) || '';
  const token = authHeader.replace(/^Bearer\s+/i, '');

  if (!token) return response(401, { message: 'Unauthorized' });

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
    return response(401, { message: 'Unauthorized' });
  }

  const branchIdFromToken = payload && payload.user && payload.user.branchId;
  if (!branchIdFromToken || branchIdFromToken !== branchIdFromPath) {
    return response(403, { message: 'Forbidden — branchId mismatch' });
  }

  const queueUrl = `https://sqs.${REGION}.amazonaws.com/${ACCOUNT_ID}/${QUEUE_PREFIX}-${branchIdFromPath}.fifo`;

  if (method === 'POST') {
    const result = await sqsClient.send(new SendMessageCommand({
      QueueUrl: queueUrl,
      MessageBody: event.body || '{}',
      MessageGroupId: branchIdFromPath,
    }));
    return response(200, { MessageId: result.MessageId, SequenceNumber: result.SequenceNumber });
  }

  if (method === 'GET') {
    const result = await sqsClient.send(new ReceiveMessageCommand({
      QueueUrl: queueUrl,
      MaxNumberOfMessages: 1,
      WaitTimeSeconds: 0,
    }));
    return response(200, { Messages: result.Messages || [] });
  }

  return response(405, { message: 'Method not allowed' });
};
