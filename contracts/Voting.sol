// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Voting is Ownable {

    // ----- Types -----
    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }

    struct Proposal {
        string description;
        uint voteCount;
    }
    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    // ----- Variables -----
    mapping(address => Voter) voters;
    Proposal[] proposals;

    WorkflowStatus public workflowStatus;
    uint public winningProposalId;

    // ----- Events -----
    event VoterRegistered(address voterAddress);

    event WorkflowStatusChange(
        WorkflowStatus previousStatus,
        WorkflowStatus newStatus
    );

    event ProposalRegistered(uint proposalId);

    event Voted(address voter, uint proposalId);

    // ----- Modifiers -----
    modifier onlyVoters() {
        require(voters[msg.sender].isRegistered,"You're not whitelisted");
        _;
    }

    // ----- Constructor -----
    constructor() Ownable(msg.sender) {
        workflowStatus = WorkflowStatus.RegisteringVoters;
    }

    // ----- Fonctions -----
    function addVoter(address _voter) external onlyOwner {
        require(_voter != address(0), "Invalid address");
        require(workflowStatus == WorkflowStatus.RegisteringVoters,"Voters registration is closed");
        require(!voters[_voter].isRegistered,"Voter already registered");

        voters[_voter].isRegistered = true;
        emit VoterRegistered(_voter);
    }
}