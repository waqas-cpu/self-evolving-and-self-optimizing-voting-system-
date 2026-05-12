import { Contract, JsonRpcProvider, Wallet, type ContractTransactionResponse } from "ethers";

const DATA_BUFFER_ABI = [
  "function commit(bytes32 batchId, bytes32 merkleRoot, uint256 leafCount) external",
  "function reveal(bytes32 batchId) external",
  "function getBatch(bytes32 batchId) view returns (bytes32,uint256,uint256,uint256,uint256,bool,bool)",
  "function REVEAL_DELAY() view returns (uint256)",
];

/**
 * Submits Merkle roots to `DataBuffer` after off-chain consensus (ethers v6).
 */
export class CommitService {
  constructor(
    private readonly provider: JsonRpcProvider,
    private readonly signer: Wallet,
    private readonly dataBufferAddress: string
  ) {}

  private buffer(): Contract {
    return new Contract(this.dataBufferAddress, DATA_BUFFER_ABI, this.signer);
  }

  async commitBatch(batchId: string, merkleRoot: string, leafCount: number): Promise<ContractTransactionResponse> {
    const c = this.buffer();
    return c.commit(batchId, merkleRoot, leafCount) as Promise<ContractTransactionResponse>;
  }

  async revealWhenDue(batchId: string, minTimestampSec: number): Promise<ContractTransactionResponse | null> {
    const c = this.buffer();
    const [, , revealAt] = await c.getBatch(batchId);
    const ra = Number(revealAt);
    if (Math.floor(Date.now() / 1000) < Math.max(ra, minTimestampSec)) {
      return null;
    }
    return c.reveal(batchId) as Promise<ContractTransactionResponse>;
  }
}
