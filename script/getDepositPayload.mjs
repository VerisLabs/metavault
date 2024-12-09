import fetch from "node-fetch";

const calculateUrl = "https://www.superform.xyz/api/proxy/deposit/calculate/";
const startUrl = "https://www.superform.xyz/api/proxy/deposit/start/";

const payload = [
  {
    user_address: "0xc9a42fEB7ba832C806F1fe47F2fFd73837CE3c21",
    from_chain_id: 8453,
    from_token_address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    amount_in: "5",
    vault_id: "8maWQ-NIWNz0pwP2GsIWf",
    bridge_slippage: 1000,
    swap_slippage: 1000,
    route_type: "output",
    exclude_liquidity_providers: [],
    is_part_of_multi_vault: false,
    refund_address:
      "0xc9a42fEB7ba832C806F1fe47F2fFd73837CE3c21",
  },
];

async function calculateRoute() {
  try {
    const response = await fetch(calculateUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const responseData = await response.text();
    console.log("Calculation response:", responseData);

    if (!response.ok) {
      throw new Error(
        `HTTP error! status: ${response.status}, message: ${responseData}`,
      );
    }

    const data = JSON.parse(responseData);

    return data;
  } catch (error) {
    console.error("There was a problem with the API call:", error);
    throw error;
  }
}

async function getTxData(route) {
  try {
    const response = await fetch(startUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(route),
    });

    const responseData = await response.text();
    console.log("TxData response:", responseData);

    if (!response.ok) {
      throw new Error(
        `HTTP error! status: ${response.status}, message: ${responseData}`,
      );
    }

    const data = JSON.parse(responseData);
    console.log("API response:", data);
    return data;
  } catch (error) {
    console.error("There was a problem with the API call:", error);
    throw error;
  }
}

async function main() {
  try {
    const response = await calculateRoute();
    const response2 = await getTxData(response);
    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
