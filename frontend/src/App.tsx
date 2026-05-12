import { useAccount, useChainId } from "wagmi";

export const App: React.FC = () => {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="title-block">
          <h1>DAO Governance Console</h1>
          <p className="subtitle">Layers 2–5 status & control surface</p>
        </div>
        <div className="wallet-block">
          <span className="pill">
            {isConnected ? "Connected" : "Not connected"}
          </span>
          {isConnected && (
            <>
              <span className="mono">
                {address?.slice(0, 6)}…{address?.slice(-4)}
              </span>
              <span className="chip">chainId: {chainId}</span>
            </>
          )}
        </div>
      </header>

      <main className="grid">
        <section className="card">
          <h2>Layer 2 — Parameters</h2>
          <p>
            This panel will show live values from <code>ParameterRegistry</code>{" "}
            (quorum, voting duration, credit caps, etc.) once ABIs + addresses
            are wired.
          </p>
          <ul className="todo-list">
            <li>Wire RPC URL in <code>.env</code> as <code>VITE_SEPOLIA_RPC_URL</code>.</li>
            <li>Add contract ABIs + addresses map.</li>
            <li>Expose read views + parameter history.</li>
          </ul>
        </section>

        <section className="card">
          <h2>Layer 5 — Failsafe Queue</h2>
          <p>
            This panel will surface <code>TimelockController</code> queued
            adjustments, veto status, and baseline hash from{" "}
            <code>BaselineRegistry</code>.
          </p>
          <ul className="todo-list">
            <li>Read <code>adjustments[id]</code> &amp; <code>adjustmentState</code>.</li>
            <li>Show countdown to <code>executableAt</code>.</li>
            <li>Visualize veto events and baseline restores.</li>
          </ul>
        </section>

        <section className="card">
          <h2>Operator Tools (Layer 3)</h2>
          <p>
            For owner / multisig only: dashboards around{" "}
            <code>Layer3Orchestrator</code> cycles and safe-set hashes. Keep this
            behind a separate route or role.
          </p>
        </section>
      </main>
    </div>
  );
};

