"""Bounded final work plus one replaceable speculative snapshot."""
from collections import deque
from threading import Condition


class Jobs:
    def __init__(self, capacity=8):
        self.capacity = capacity
        self.finals = deque()
        self.partial = None
        self.closed = False
        self.condition = Condition()

    def put(self, job, final):
        with self.condition:
            if self.closed:
                return False
            if final:
                if len(self.finals) >= self.capacity:
                    return False
                self.finals.append(job)
                if self.partial is not None and self.partial[0] == job[0]:
                    self.partial = None
            else:
                self.partial = job
            self.condition.notify()
            return True

    def get(self):
        with self.condition:
            self.condition.wait_for(lambda: self.closed or self.finals or self.partial is not None)
            if self.finals:
                return self.finals.popleft(), True
            if self.partial is not None:
                job, self.partial = self.partial, None
                return job, False
            return None

    def close(self):
        with self.condition:
            self.partial = None
            self.closed = True
            self.condition.notify_all()
