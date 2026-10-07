const AWS = require('aws-sdk');
const mongoose = require('mongoose');
const { Schema } = require('mongoose');
const moment = require('moment');

//Variables
const daysBefore = parseInt(process.env.DAYSBEFORE, 10) || 15;
// UTC-3, fixed, no DST (America/Argentina/Cordoba). Explicit undefined-check, not `|| -180` -
// that pattern would silently ignore a deliberate ARG_OFFSET_MINUTES=0 (falsy but valid).
const ARG_OFFSET_MINUTES =
  process.env.ARG_OFFSET_MINUTES !== undefined
    ? parseInt(process.env.ARG_OFFSET_MINUTES, 10)
    : -180;
const user = process.env.MONGO_USER;
const passwd = process.env.MONGO_PASSWD;
const host = process.env.HOST;
const database = process.env.DATABASE;
const region = process.env.REGION;
const bucket = process.env.BUCKET;
const connString = `mongodb+srv://${user}:${passwd}@${host}/${database}`;

const connectDB = () => {
  return mongoose.connect(connString, {
    useNewUrlParser: true,
    useUnifiedTopology: true,
  });
};

const newsSchema = mongoose.model(
  'news',
  new Schema(
    {
      typeId: {
        type: Number,
        required: true,
      },
      order: {
        type: Object,
        required: true,
      },
      branchId: {
        type: Number,
        required: true,
      },
      rejectedMessageId: {
        type: Number,
      },
      viewed: {
        type: Date,
      },
      traces: [
        {
          update: {
            type: Object,
          },
          createdAt: {
            type: Date,
            default: Date.now,
          },
        },
      ],
    },
    {
      strict: false,
      timestamps: true,
    }
  )
);

const retrieveData = (from, to) => {
  return newsSchema
    .find({
      $and: [
        { updatedAt: { $gt: new Date(from) } },
        { updatedAt: { $lte: new Date(to) } },
      ],
    })
    .lean();
};

const saveS3 = (momentDate, stringNew, suffix = '') => {
  const parseMb = (bytes) => (bytes / 1048576).toFixed(2);
  const collection = 'news';
  //Parse news file to buffer
  const day = momentDate.format('DD');
  const month = momentDate.format('MM');
  const year = momentDate.format('YYYY');
  const filename = `news${year + month + day}${suffix}.json`;
  const directory = `${bucket}/${collection}/${year}/${month}`;

  console.log('Going to insert: ', filename);
  //Push to S3
  AWS.config.setPromisesDependency();
  AWS.config.update({
    region: region,
    httpOptions: {
      timeout: 180000,
    },
  });
  const s3 = new AWS.S3();
  return s3
    .putObject({
      Bucket: directory,
      Body: stringNew,
      Key: filename,
    })
    .on('httpUploadProgress', (event) => {
      console.info(
        `${directory} - ${filename} - Uploaded ${parseMb(
          event.loaded
        )} mb out of ${parseMb(event.total)} mb.`
      );
    })
    .promise();
};

const orderMapper = (order) => {
  let parsedOrder = {};
  parsedOrder.order = {};
  parsedOrder.order.id = order.order.id;
  parsedOrder.order.originalid = order.order.originalId;
  parsedOrder.order.displayid = order.order.displayId;
  parsedOrder.order.platformid = parseInt(order.order.platformId, 10) || -1;
  parsedOrder.order.statusid = parseInt(order.order.statusId, 10) || -1;
  parsedOrder.order.ordertime = order.order.orderTime;
  parsedOrder.order.deliverytime = order.order.deliveryTime;
  parsedOrder.order.pickuponshop = order.order.pickupOnShop;
  parsedOrder.order.pickupdateonshop = order.order.pickupDateOnShop;
  parsedOrder.order.preorder = order.order.preOrder;
  parsedOrder.order.observations = order.order.observations;
  parsedOrder.order.owndelivery = order.order.ownDelivery;
  const customer = order.order.customer;
  parsedOrder.order.customer = {
    id: customer.id,
    name: customer.name,
    address: customer.address,
    phone: customer.phone,
    email: customer.email,
    dni: customer.dni,
  };
  parsedOrder.order.details = order.order.details.map((detail) => {
    return {
      productid: detail.productId,
      count: detail.count,
      price: detail.price,
      promo: detail.promo,
      groupid: detail.groupId,
      discount: detail.discount,
      description: detail.description,
      note: detail.note,
      sku: parseInt(detail.sku, 10) || -1,
      optionaltext: detail.optionalText,
      canje: detail.canje,
    };
  });
  const payment = order.order.payment;
  parsedOrder.order.payment = {
    discount: parseFloat(payment.discount) || 0,
    voucher: payment.voucher,
    remaining: parseFloat(payment.remaining) || 0,
    partial: parseFloat(payment.partial) || 0,
    typeid: parseInt(payment.typeId, 10) || -1,
    online: payment.online,
    currency: payment.currency,
    note: payment.note,
  };
  parsedOrder.order.driver = order.order.driver;
  parsedOrder.order.totalamount = parseFloat(order.order.totalAmount) || 0;

  parsedOrder.typeId = parseInt(order.typeId, 10) || -1;
  parsedOrder.branchId = parseInt(order.branchId, 10) || -1;
  parsedOrder.traces = order.traces;
  parsedOrder.createdat = order.createdAt;
  parsedOrder.updatedat = order.updatedAt;
  parsedOrder.viewed = order.viewed;

  parsedOrder.extradata = {
    branch: order.extraData.branch,
    chain: order.extraData.chain,
    platform: order.extraData.platform,
    state: order.extraData.state,
    client: order.extraData.client,
    region: order.extraData.region,
  };
  if (order.extraData.rejected)
    parsedOrder.extradata.rejected = {
      rejectmessageid:
        parseInt(order.extraData.rejected.rejectMessageId, 10) || -1,
      rejectmessagedescription:
        order.extraData.rejected.rejectMessageDescription,
      rejectmessagenote: order.extraData.rejected.rejectMessageNote,
      entity: order.extraData.rejected.entity,
    };

  return parsedOrder;
};

// Offset 0 = UTC midnight boundary (pre-GITIN-1970 behavior), kept for backwards
// compatibility alongside the current ARG_OFFSET_MINUTES (-180) file.
const UTC0_OFFSET_MINUTES = 0;

const computeBoundaries = (offsetMinutes, day) => {
  const zeroHour = { hour: 0, minute: 0, second: 0, millisecond: 0 };
  const momentDate = moment().utcOffset(offsetMinutes).set(zeroHour).add(day, 'days');
  const dateGt = momentDate.clone().format('YYYY-MM-DD HH:mm:ss.SSSZ');
  const dateLte = momentDate.clone().add(1, 'days').format('YYYY-MM-DD HH:mm:ss.SSSZ');
  return { momentDate, dateGt, dateLte };
};

const fetchAndSave = async (offsetMinutes, day, suffix, label) => {
  const { momentDate, dateGt, dateLte } = computeBoundaries(offsetMinutes, day);
  const data = await retrieveData(dateGt, dateLte);
  //Generate news file in json separated with enters.
  const stringNew = data
    .map((order) => orderMapper(order))
    .map((order) => JSON.stringify(order) + '\n')
    .join('');

  //Avoid pushing a file without length; skip this file only, not the whole batch
  if (stringNew.length < 10) return;

  console.time('pushS3' + label);
  await saveS3(momentDate, stringNew, suffix);
  console.timeEnd('pushS3' + label);
};

const run = async () => {
  try {
    const arrayDaysBefore = Array.from(Array(daysBefore + 1).keys())
      .splice(1)
      .reverse();
    await connectDB();

    console.time('total');
    let i = 0;
    for (const rawDay of arrayDaysBefore) {
      const day = -rawDay;

      // Backwards-compatible plain-named file, UTC-midnight boundary
      await fetchAndSave(UTC0_OFFSET_MINUTES, day, '', 'utc0-' + i.toString());

      // Current -3 file, Argentina/UTC-3 boundary
      await fetchAndSave(ARG_OFFSET_MINUTES, day, '-3', 'arg-' + i.toString());

      i++;
    }
    console.timeEnd('total');
  } catch (error) {
    console.log(error);
  }
};
module.exports = { run };
