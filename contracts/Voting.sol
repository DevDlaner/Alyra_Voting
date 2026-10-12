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
    // --- Admin ---
    function addVoter(address _voter) external onlyOwner {
        require(_voter != address(0), "Invalid address");
        require(workflowStatus == WorkflowStatus.RegisteringVoters,"Voters registration is closed");
        require(!voters[_voter].isRegistered,"Voter already registered");

        voters[_voter].isRegistered = true;
        emit VoterRegistered(_voter);
    }

    // - Changements de status ---
    function _changeWorkflowStatus(WorkflowStatus _newStatus) internal {
        WorkflowStatus previousStatus = workflowStatus;
        workflowStatus = _newStatus;

        emit WorkflowStatusChange(previousStatus, _newStatus);
    }


    function startProposals() external onlyOwner {
        require(
            workflowStatus == WorkflowStatus.RegisteringVoters,
            "Voters registration phase is not active"
        );

        _changeWorkflowStatus(WorkflowStatus.ProposalsRegistrationStarted);
    }


    function endProposals() external onlyOwner {
        require(
            workflowStatus == WorkflowStatus.ProposalsRegistrationStarted,
            "Proposals registration has not started"
        );
        // vu qu'on peut pas revenir en arriere, je bloque la fin des registration si aucune proposition...
        require(proposals.length > 0, "No proposal registered");

        _changeWorkflowStatus(WorkflowStatus.ProposalsRegistrationEnded);
    }


    function startVoting() external onlyOwner {
        require(
            workflowStatus == WorkflowStatus.ProposalsRegistrationEnded,
            "Proposals registration is not ended"
        );
        // doublons, mais en cas d'editions des proposal en externe entre la fin des propositions, et le debut du vote...
        // dans ce cadre precis, pas utile, mais je prefere le mettre au cas ou un jour je veuille reutiliser le code...
        require(proposals.length > 0, "No proposal registered");

        _changeWorkflowStatus(WorkflowStatus.VotingSessionStarted);
    }


    function endVoting() external onlyOwner {
        require(
            workflowStatus == WorkflowStatus.VotingSessionStarted,
            "Voting session has not started"
        );

        _changeWorkflowStatus(WorkflowStatus.VotingSessionEnded);
    }

    // décompte...
    function tallyVotes() external onlyOwner {
        require(
            workflowStatus == WorkflowStatus.VotingSessionEnded,
            "Voting session is not ended"
        );

        uint highestVoteCount = proposals[0].voteCount;
        winningProposalId = 0;

        // En cas d'égalité, on conserve la premiere proposition...
        // fonctionne en cas de 0 votes du coup...
        for (uint i = 1; i < proposals.length; i++) {
            if (proposals[i].voteCount > highestVoteCount) {
                highestVoteCount = proposals[i].voteCount;
                winningProposalId = i;
            }
        }

        _changeWorkflowStatus(WorkflowStatus.VotesTallied);
    }

    // --- Voters ---
    function addProposal(string memory _description) external onlyVoters {
        require(bytes(_description).length > 0, "Invalid proposal");
        require(workflowStatus == WorkflowStatus.ProposalsRegistrationStarted,"You can't add proposal right now");

        proposals.push(Proposal(_description,0));
        emit ProposalRegistered(proposals.length-1);
    }
    
    function vote(uint _voteId) external onlyVoters {
        require(_voteId <proposals.length, "Invalid vote (proposal ID too high)");
        require(workflowStatus == WorkflowStatus.VotingSessionStarted,"This vote isn't active right now");
        require(!voters[msg.sender].hasVoted,"Voter already voted");

        proposals[_voteId].voteCount++;
        voters[msg.sender].hasVoted=true;
        voters[msg.sender].votedProposalId=_voteId;
        emit Voted(msg.sender, _voteId);
    }
}