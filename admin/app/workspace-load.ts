export type WorkspaceLoadTicket = {
  profileId: string;
  generation: number;
};

export class WorkspaceLoadGuard {
  private profileId = "";
  private generation = 0;

  begin(profileId: string): WorkspaceLoadTicket {
    this.profileId = profileId;
    this.generation += 1;
    return this.current();
  }

  current(): WorkspaceLoadTicket {
    return {
      profileId: this.profileId,
      generation: this.generation,
    };
  }

  invalidate() {
    this.profileId = "";
    this.generation += 1;
  }

  isCurrent(ticket: WorkspaceLoadTicket) {
    return (
      ticket.profileId === this.profileId &&
      ticket.generation === this.generation
    );
  }
}
