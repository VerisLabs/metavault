import { ERC1155 } from "solady/tokens/ERC1155.sol";

contract MockSuperPositions is ERC1155 {
    function uri(uint256 id) public view override returns (string memory) {
        return "";
    }

    function mintSingle(address receiverAddress_, uint256 id_, uint256 amount_) public {
        _mint(receiverAddress_, id_, amount_, "");
    }

    function mintBatch(address receiverAddress_, uint256[] memory ids_, uint256[] memory amounts_) external {
        for (uint256 i = 0; i < ids_.length; i++) {
            mintSingle(receiverAddress_, ids_[i], amounts_[i]);
        }
    }

    function burnSingle(address srcSender_, uint256 id_, uint256 amount_) public {
        _burn(srcSender_, id_, amount_);
    }

    function burnBatch(address srcSender_, uint256[] memory ids_, uint256[] memory amounts_) external {
        for (uint256 i = 0; i < ids_.length; i++) {
            burnSingle(srcSender_, ids_[i], amounts_[i]);
        }
    }
}
