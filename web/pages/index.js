import Head from "next/head";
import { useEffect, useState } from "react";
import Navbar from "@/components/Navbar";
import { getAllDomainInfos } from "../flow/scripts";

export default function Home() {
  // Create a state variable for all the DomainInfo structs
  // Initialize it to an empty array
  const [domainInfos, setDomainInfos] = useState([]);

  // Load all the DomainInfo's by running the Cadence script
  // when the page is loaded
  useEffect(() => {
    async function fetchDomains() {
      const domains = await getAllDomainInfos();
      setDomainInfos(domains);
    }

    fetchDomains();
  }, []);

  return (
    <div>
      <Head>
        <title>Flow Name Service</title>
        <meta name="description" content="Flow Name Service" />
        <link rel="icon" href="/favicon.ico" />
      </Head>

      <Navbar />

      <main>
        <h1>All Registered Domains</h1>
        <p>This is sample project created on <a href="https://flow.com/" target="_blank" rel="noreferrer">Flow</a> blockchain which have been deployed on <a href="https://testnet.flowscan.org/contract/A.76a74722076aefdd.Domains" target="_blank" rel="noreferrer">Flow Testnet</a>.<br />
          To play around, install <a href="https://lilico.app/" target="_blank" rel="noreferrer">Lilico</a> wallet, fund some <a href="https://testnet-faucet.onflow.org/" _target="blank" rel="noreferrer">Flow test tokens</a>, connect wallet and purchase some .fns</p>

        <div className="grid">
          {
            // If no domains were found, display a message highlighting that
            domainInfos.length === 0 ? (
              <p>No FNS Domains have been registered yet</p>
            ) : (
              // Otherwise, loop over the array, and render information
              // about each domain
              domainInfos.map((di, idx) => (
                <article key={idx}>
                  <header>
                    <h4>{di.id} - {di.name}</h4>
                  </header>
                  <p>Owner: {di.owner}</p>
                  <p>Linked Address: {di.address ? di.address : "None"}</p>
                  <p>Bio: {di.bio ? di.bio : "None"}</p>
                  {/* Parse the timestamps as human-readable dates */}
                  <p>
                    Created At:{" "}
                    {new Date(parseInt(di.createdAt) * 1000).toLocaleDateString()}
                  </p>
                  <p>
                    Expires At:{" "}
                    {new Date(parseInt(di.expiresAt) * 1000).toLocaleDateString()}
                  </p>
                </article>
              ))
            )}
        </div>
      </main>
    </div>
  );
}